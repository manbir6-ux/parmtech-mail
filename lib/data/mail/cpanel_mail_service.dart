import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;

import '../accounts/mail_account.dart' as model;
import 'mail_presentation.dart';
import 'mail_fetch_guard.dart';

/// A small file selected for SMTP submission. Never saved to mail caches.
class OutgoingMailAttachment {
  const OutgoingMailAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class MailItem {
  const MailItem({
    required this.sender,
    required this.senderAddress,
    required this.subject,
    required this.body,
    required this.time,
    required this.sentAt,
    required this.unread,
    this.uid,
    this.mailboxPath = 'INBOX',
    this.starred = false,
    this.messageId = '',
    this.inReplyTo = '',
    this.references = '',
    this.replyToAddress = '',
  });

  final String sender;
  final String senderAddress;
  final String subject;
  final String body;
  final String time;
  final DateTime? sentAt;
  final bool unread;
  final int? uid;
  final String mailboxPath;
  final bool starred;
  final String messageId;
  final String inReplyTo;
  final String references;
  final String replyToAddress;

  String get identity => uid == null
      ? '$mailboxPath|$senderAddress|$subject|${sentAt?.millisecondsSinceEpoch ?? time}'
      : '$mailboxPath|$uid';

  Map<String, Object?> toJson() => {
        'sender': sender,
        'senderAddress': senderAddress,
        'subject': subject,
        'body': body,
        'time': time,
        'sentAt': sentAt?.toIso8601String(),
        'unread': unread,
        'uid': uid,
        'mailboxPath': mailboxPath,
        'starred': starred,
        'messageId': messageId,
        'inReplyTo': inReplyTo,
        'references': references,
        'replyToAddress': replyToAddress,
      };

  factory MailItem.fromJson(Map<String, dynamic> json) => MailItem(
        sender: json['sender'] as String? ?? '',
        senderAddress: json['senderAddress'] as String? ?? '',
        subject: json['subject'] as String? ?? '(no subject)',
        body: json['body'] as String? ?? '',
        time: json['time'] as String? ?? '',
        sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
        unread: json['unread'] as bool? ?? false,
        uid: json['uid'] as int?,
        mailboxPath: json['mailboxPath'] as String? ?? 'INBOX',
        starred: json['starred'] as bool? ?? false,
        messageId: json['messageId'] as String? ?? '',
        inReplyTo: json['inReplyTo'] as String? ?? '',
        references: json['references'] as String? ?? '',
        replyToAddress: json['replyToAddress'] as String? ?? '',
      );

  MailItem copyWith({bool? unread, bool? starred}) => MailItem(
        sender: sender,
        senderAddress: senderAddress,
        subject: subject,
        body: body,
        time: time,
        sentAt: sentAt,
        unread: unread ?? this.unread,
        uid: uid,
        mailboxPath: mailboxPath,
        starred: starred ?? this.starred,
        messageId: messageId,
        inReplyTo: inReplyTo,
        references: references,
        replyToAddress: replyToAddress,
      );
}

class MailFolder {
  const MailFolder({
    required this.name,
    required this.path,
    required this.unread,
  });

  final String name;
  final String path;
  final int unread;
}

/// Direct, device-to-provider IMAP/SMTP transport. TLS validation stays enabled.
/// Host fallback happens only when the TCP/TLS connection itself fails; an
/// authentication rejection is returned immediately.
class CpanelMailService {
  static const _connectTimeout = Duration(seconds: 20);
  static const _responseTimeout = Duration(seconds: 25);
  static const _closeTimeout = Duration(seconds: 3);

  Future<model.MailAccount> verify(model.MailAccount account) async {
    final session = await _connectAndLogin(account);
    try {
      await session.client.selectInbox();
      return model.MailAccount(
        email: account.email.trim(),
        password: account.password,
        imapHost: model.parmTechMailServerHost,
        smtpHost: model.parmTechMailServerHost,
        displayName: account.displayName,
        useCustomServer: false,
      );
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<List<MailFolder>> listFolders(model.MailAccount account) async {
    final session = await _connectAndLogin(account);
    try {
      final boxes = await session.client.listMailboxes(recursive: true);
      return deduplicateMailFolders(
        boxes.map(
            (box) => MailFolder(
              name: box.encodedName,
              path: box.encodedPath,
              unread: box.messagesUnseen,
            ),
          ),
      );
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<List<MailItem>> fetchInbox(
    model.MailAccount account, {
    int count = 40,
  }) => fetchFolder(account, 'INBOX', count: count);

  /// Gets an accurate server-side unread count without downloading message
  /// bodies. This keeps background polling lightweight across multiple accounts.
  Future<int> countUnread(model.MailAccount account) async {
    final session = await _connectAndLogin(account);
    try {
      await session.client.selectInbox();
      final result = await session.client.searchMessages(
        searchCriteria: 'UNSEEN',
        responseTimeout: _responseTimeout,
      );
      return result.count ?? 0;
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<List<MailItem>> fetchFolder(
    model.MailAccount account,
    String folderPath, {
    int count = 40,
  }) async {
    final session = await _connectAndLogin(account);
    try {
      // SELECT can report zero EXISTS after another device emptied the folder.
      // Calling fetchRecentMessages in that state generates FETCH 0:1, which
      // cPanel correctly rejects with BAD Invalid messageset.
      final result = await guardedImapFetch<List<mail.MimeMessage>>(
        selectAndCount: () async {
          final box = folderPath.toUpperCase() == 'INBOX'
              ? await session.client.selectInbox()
              : await session.client.selectMailboxByPath(folderPath);
          return box.messagesExists;
        },
        fetch: () async {
          final response = await session.client.fetchRecentMessages(
            messageCount: count,
            criteria: '(UID FLAGS INTERNALDATE BODY.PEEK[])',
            responseTimeout: _responseTimeout,
          );
          return response.messages;
        },
        empty: () => <mail.MimeMessage>[],
      );
      return result.reversed
          .map((message) {
            final plainBody = message.decodeTextPlainPart()?.trim() ?? '';
            final body = plainBody.isNotEmpty
                ? plainBody
                : htmlMailToText(message.decodeTextHtmlPart() ?? '');
            final addresses = message.from;
            final from = addresses == null || addresses.isEmpty
                ? null
                : addresses.first;
            final senderAddress = from?.email.trim() ?? '';
            final sender = displaySenderName(
              personalName: from?.personalName,
              email: senderAddress,
              fallback: account.email,
            );
            final subject = message.decodeSubject()?.trim();
            DateTime? sentAt;
            try {
              sentAt = message.decodeDate();
            } catch (_) {
              // Fall back to the IMAP server date for malformed Date headers.
            }
            sentAt ??= parseImapInternalDate(message.internalDate);
            return MailItem(
              sender: sender,
              senderAddress: senderAddress,
              subject: subject == null || subject.isEmpty
                  ? '(no subject)'
                  : subject,
              body: body.trim(),
              time: formatMailTimestamp(sentAt),
              sentAt: sentAt,
              unread: !message.isSeen,
              uid: message.uid,
              mailboxPath: folderPath,
              starred: message.isFlagged,
              messageId: message.getHeaderValue('Message-ID')?.trim() ?? '',
              inReplyTo: message.getHeaderValue('In-Reply-To')?.trim() ?? '',
              references: message.getHeaderValue('References')?.trim() ?? '',
              replyToAddress: message.replyTo?.firstOrNull?.email.trim() ?? senderAddress,
            );
          })
          .toList(growable: false);
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<void> setRead(model.MailAccount account, MailItem item, bool read) =>
      _withUid(account, item, (client, sequence) async {
        if (read) {
          await client.uidMarkSeen(sequence);
        } else {
          await client.uidMarkUnseen(sequence);
        }
      });

  Future<void> setStarred(model.MailAccount account, MailItem item, bool starred) =>
      _withUid(account, item, (client, sequence) async {
        if (starred) {
          await client.uidMarkFlagged(sequence);
        } else {
          await client.uidMarkUnflagged(sequence);
        }
      });

  Future<void> moveMessage(model.MailAccount account, MailItem item, String targetPath) =>
      _withUid(account, item, (client, sequence) async {
        await client.uidMove(sequence, targetMailboxPath: targetPath);
      });

  Future<void> deleteMessage(model.MailAccount account, MailItem item) async {
    await deleteMessages(account, [item]);
  }

  Future<bool> _uidExists(mail.ImapClient client, int uid) async {
    final found = await client.uidSearchMessages(
      searchCriteria: 'UID $uid',
      responseTimeout: _responseTimeout,
    );
    return found.matchingSequence?.isNotEmpty ?? false;
  }

  /// Server truth wins: a message missing from its original IMAP folder is
  /// already gone and should be removed from the device cache without error.
  Future<void> deleteMessages(model.MailAccount account, List<MailItem> items) async {
    if (items.isEmpty) return;
    final validItems = items.where((item) => item.uid != null && item.uid! > 0)
        .toList(growable: false);
    if (validItems.isEmpty) return; // legacy offline entries
    final folders = await listFolders(account);
    final trash = folders.where((folder) =>
        RegExp(r'^(trash|deleted|deleted items|bin)$', caseSensitive: false)
            .hasMatch(folder.name.split(RegExp(r'[/\\.]')).last));
    final session = await _connectAndLogin(account);
    try {
      final byFolder = <String, List<MailItem>>{};
      for (final item in validItems) {
        byFolder.putIfAbsent(item.mailboxPath, () => []).add(item);
      }
      for (final entry in byFolder.entries) {
        final mailbox = entry.key.toUpperCase() == 'INBOX'
            ? await session.client.selectInbox()
            : await session.client.selectMailboxByPath(entry.key);
        if (mailbox.messagesExists <= 0) continue;
        for (final item in entry.value) {
          final uid = item.uid!;
          if (!await _uidExists(session.client, uid)) continue;
          final sequence = mail.MessageSequence.fromRange(
            uid, uid, isUidSequence: true,
          );
          if (trash.isNotEmpty && trash.first.path != entry.key) {
            await session.client.uidMove(
              sequence,
              targetMailboxPath: trash.first.path,
            );
          } else {
            await session.client.uidMarkDeleted(sequence);
            await session.client.uidExpunge(sequence);
          }
        }
      }
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<void> createFolder(model.MailAccount account, String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.contains('/') || clean.contains('\\')) {
      throw const MailConnectionException('Enter a valid folder name.');
    }
    final session = await _connectAndLogin(account);
    try {
      await session.client.createMailbox(clean);
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<void> _withUid(
    model.MailAccount account,
    MailItem item,
    Future<void> Function(mail.ImapClient, mail.MessageSequence) action,
  ) async {
    final uid = item.uid;
    if (uid == null || uid <= 0) {
      throw const MailConnectionException('Refresh this message before applying an action.');
    }
    final session = await _connectAndLogin(account);
    try {
      if (item.mailboxPath.toUpperCase() == 'INBOX') {
        await session.client.selectInbox();
      } else {
        await session.client.selectMailboxByPath(item.mailboxPath);
      }
      await action(session.client,
          mail.MessageSequence.fromRange(uid, uid, isUidSequence: true));
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<void> send(
    model.MailAccount account, {
    required String to,
    required String subject,
    required String body,
    List<OutgoingMailAttachment> attachments = const [],
    String? inReplyTo,
    String? references,
  }) async {
    if (attachments.fold<int>(0, (size, file) => size + file.bytes.length) >
        20 * 1024 * 1024) {
      throw const MailConnectionException(
        'Attachments exceed the 20 MB total size limit.',
      );
    }
    if (!model.isValidMailAddress(to)) {
      throw const MailConnectionException('Enter a valid recipient email address.');
    }
    // Never send mailbox credentials to user-entered or inferred servers.
    const candidates = <String>{model.parmTechMailServerHost};
    final connectionErrors = <String>[];

    for (final host in candidates) {
      final client = mail.SmtpClient(host, isLogEnabled: false);
      try {
        await client.connectToServer(
          host,
          model.MailAccount.smtpPort,
          isSecure: true,
          timeout: _connectTimeout,
        );
      } catch (error) {
        connectionErrors.add('$host:465 (${_describeConnectionFailure(error)})');
        try {
          await client.disconnect();
        } catch (_) {}
        continue;
      }

      try {
        await _withSmtpTimeout(client, client.ehlo);
        if (client.serverInfo.supportsAuth(mail.AuthMechanism.plain)) {
          await _withSmtpTimeout(
            client,
            () => client.authenticate(
              account.email.trim(),
              account.password,
              mail.AuthMechanism.plain,
            ),
          );
        } else if (client.serverInfo.supportsAuth(mail.AuthMechanism.login)) {
          await _withSmtpTimeout(
            client,
            () => client.authenticate(
              account.email.trim(),
              account.password,
              mail.AuthMechanism.login,
            ),
          );
        } else {
          throw const MailConnectionException(
            'The outgoing server does not offer password authentication.',
          );
        }

        final html = '<p>${_escapeHtml(body).replaceAll('\n', '<br>')}</p>';
        final builder = attachments.isEmpty
            ? mail.MessageBuilder.prepareMultipartAlternativeMessage(
                plainText: body,
                htmlText: html,
              )
            : (mail.MessageBuilder.prepareMultipartMixedMessage()
              ..addMultipartAlternative(plainText: body, htmlText: html));
        builder.from = [mail.MailAddress('', account.email.trim())];
        builder.to = [mail.MailAddress('', to.trim())];
        builder.subject = subject;
        // RFC 5322: these headers let Yahoo, Gmail and other mail clients
        // place replies inside the existing conversation.
        if (inReplyTo != null && inReplyTo.trim().isNotEmpty) {
          builder.addHeader('In-Reply-To', inReplyTo.trim());
          final prior = references?.trim() ?? '';
          final threadRefs = prior.isEmpty ? inReplyTo.trim() : '$prior ${inReplyTo.trim()}';
          builder.addHeader('References', threadRefs);
        }
        for (final file in attachments) {
          final name = file.name.replaceAll(RegExp(r'[\r\n\\/]'), '_');
          builder.addBinary(
            file.bytes,
            mail.MediaType.guessFromFileName(name),
            filename: name,
          );
        }
        final response = await _withSmtpTimeout(
          client,
          () => client.sendMessage(builder.buildMimeMessage()),
        );
        if (!response.isOkStatus) {
          throw const MailConnectionException(
            'The outgoing server rejected the message.',
          );
        }
        return;
      } finally {
        await _closeSmtp(client);
      }
    }

    throw MailConnectionException(
      'Could not reach a secure SMTP server. ${connectionErrors.join('; ')}',
    );
  }

  Future<_ImapSession> _connectAndLogin(model.MailAccount account) async {
    // Single-server private client. This remains true for imported backups
    // and accounts saved by older versions of the app.
    const hosts = <String>{model.parmTechMailServerHost};
    final connectionErrors = <String>[];
    var sawTlsFailure = false;

    for (final host in hosts) {
      final client = mail.ImapClient(
        isLogEnabled: false,
        defaultResponseTimeout: _responseTimeout,
        defaultWriteTimeout: _responseTimeout,
      );
      try {
        await _connectImap(client, host);
      } catch (error) {
        final hint = _describeConnectionFailure(error);
        if (error is HandshakeException || error is TlsException ||
            hint.contains('certificate')) {
          sawTlsFailure = true;
        }
        connectionErrors.add('$host:993 ($hint)');
        continue;
      }

      try {
        await client.login(account.email.trim(), account.password);
        return _ImapSession(client, host);
      } catch (_) {
        await _closeImap(client);
        rethrow;
      }
    }

    final recommendation = sawTlsFailure
        ? 'The ParmTech mail server certificate could not be verified. '
          'The server administrator should check the hostname and TLS certificate.'
        : 'Could not contact the private ParmTech mail server. '
          'Check your connection or contact the server administrator.';
    throw MailConnectionException(
      'Could not connect to IMAP securely. $recommendation '
      'Tried: ${connectionErrors.join('; ')}.',
    );
  }

  /// A safe, password-free diagnostic for the account setup screen.
  static String _describeConnectionFailure(Object error) {
    if (error is HandshakeException || error is TlsException) {
      return 'TLS certificate or handshake failed';
    }
    if (error is TimeoutException) return 'connection timed out';
    if (error is SocketException) {
      final lower = error.message.toLowerCase();
      if (lower.contains('lookup') || lower.contains('resolve') ||
          lower.contains('host not found')) {
        return 'hostname could not be resolved';
      }
      return 'connection refused or unreachable';
    }
    final lower = error.toString().toLowerCase();
    if (lower.contains('certificate') || lower.contains('handshake') ||
        lower.contains('tls')) {
      return 'TLS certificate or handshake failed';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'connection timed out';
    }
    return 'server unavailable';
  }

  Future<void> _connectImap(mail.ImapClient client, String host) async {
    try {
      await client.connectToServer(
        host,
        model.MailAccount.imapPort,
        isSecure: true,
        timeout: _connectTimeout,
      );
    } catch (_) {
      await _disconnectImap(client);
      rethrow;
    }
  }

  Future<void> _closeImap(mail.ImapClient client) async {
    try {
      await client.logout().timeout(_closeTimeout);
    } catch (_) {
      await _disconnectImap(client);
    }
  }

  Future<void> _closeSmtp(mail.SmtpClient client) async {
    try {
      await client.quit().timeout(_closeTimeout);
    } catch (_) {
      try {
        await client.disconnect().timeout(_closeTimeout);
      } catch (_) {}
    }
  }

  Future<void> _disconnectImap(mail.ImapClient client) async {
    try {
      await client.disconnect().timeout(_closeTimeout);
    } catch (_) {}
  }

  Future<T> _withSmtpTimeout<T>(
    mail.SmtpClient client,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation().timeout(_responseTimeout);
    } on TimeoutException {
      try {
        await client.disconnect().timeout(_closeTimeout);
      } catch (_) {}
      rethrow;
    }
  }

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

/// Collapses duplicate cPanel mailbox aliases such as `Spam`, `Junk`, and
/// `INBOX.spam` into one visible folder while retaining a usable server path.
List<MailFolder> deduplicateMailFolders(Iterable<MailFolder> folders) {
  final unique = <MailFolder>[];
  final indices = <String, int>{};
  for (final folder in folders) {
    final rawName = folder.name.trim().isEmpty ? folder.path : folder.name;
    final leaf = rawName
        .split(RegExp(r'[/\\.]'))
        .last
        .replaceAll('"', '')
        .trim()
        .toLowerCase();
    final category = switch (leaf) {
      'inbox' => 'inbox',
      'sent' || 'sent items' || 'sent mail' => 'sent',
      'draft' || 'drafts' => 'drafts',
      'trash' || 'deleted items' || 'deleted messages' => 'trash',
      'junk' || 'spam' => 'spam',
      'archive' => 'archive',
      _ => '',
    };
    final normalizedPath = folder.path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .join('/')
        .toLowerCase();
    final key = category.isEmpty ? 'path:$normalizedPath' : 'system:$category';
    final existingIndex = indices[key];
    if (existingIndex == null) {
      indices[key] = unique.length;
      unique.add(folder);
    } else if (folder.unread > unique[existingIndex].unread) {
      unique[existingIndex] = folder;
    }
  }
  return List<MailFolder>.unmodifiable(unique);
}

class _ImapSession {
  const _ImapSession(this.client, this.host);

  final mail.ImapClient client;
  final String host;
}

class MailConnectionException implements Exception {
  const MailConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

String friendlyMailError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  final lower = text.toLowerCase();

  if (error is MailConnectionException) return error.message;

  if (lower.contains('auth') ||
      lower.contains('login') ||
      lower.contains('credential')) {
    return 'Email or password was rejected. Check the mailbox password in cPanel.';
  }
  if (lower.contains('certificate') || lower.contains('handshake')) {
    return 'Secure TLS connection failed. Check the hosting server and its certificate.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'The mail server did not respond in time. Check your connection and try again.';
  }
  if (lower.contains('host lookup') ||
      lower.contains('socketfailed') ||
      lower.contains('no address associated with hostname')) {
    return 'The mail server name could not be resolved. Check your internet connection and hosting server settings.';
  }
  return text;
}
