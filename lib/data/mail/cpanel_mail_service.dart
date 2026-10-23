import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;

import '../accounts/mail_account.dart' as model;
import 'mail_presentation.dart';

class MailItem {
  const MailItem({
    required this.sender,
    required this.senderAddress,
    required this.subject,
    required this.body,
    required this.time,
    required this.sentAt,
    required this.unread,
  });

  final String sender;
  final String senderAddress;
  final String subject;
  final String body;
  final String time;
  final DateTime? sentAt;
  final bool unread;
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
        imapHost: session.host,
        smtpHost: session.host,
        displayName: account.displayName,
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
      if (folderPath.toUpperCase() == 'INBOX') {
        await session.client.selectInbox();
      } else {
        await session.client.selectMailboxByPath(folderPath);
      }
      final result = await session.client.fetchRecentMessages(
        messageCount: count,
        criteria: 'BODY.PEEK[]',
        responseTimeout: _responseTimeout,
      );
      return result.messages.reversed
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
            sentAt ??= DateTime.tryParse(message.internalDate ?? '')?.toLocal();
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
            );
          })
          .toList(growable: false);
    } finally {
      await _closeImap(session.client);
    }
  }

  Future<void> send(
    model.MailAccount account, {
    required String to,
    required String subject,
    required String body,
  }) async {
    final candidates = <String>{
      ...model.cPanelHostCandidates(account.email).map((e) => e.host),
      account.smtpHost,
    };
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
        connectionErrors.add('$host: $error');
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

        final message =
            mail.MessageBuilder.prepareMultipartAlternativeMessage(
                plainText: body,
                htmlText:
                    '<p>${_escapeHtml(body).replaceAll('\n', '<br>')}</p>',
              )
              ..from = [mail.MailAddress('', account.email.trim())]
              ..to = [mail.MailAddress('', to.trim())]
              ..subject = subject;

        final response = await _withSmtpTimeout(
          client,
          () => client.sendMessage(message.buildMimeMessage()),
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
    final hosts = <String>{
      ...model.cPanelHostCandidates(account.email).map((candidate) => candidate.host),
      account.imapHost,
    }.where((host) => host.trim().isNotEmpty);
    final connectionErrors = <String>[];

    for (final host in hosts) {
      final client = mail.ImapClient(
        isLogEnabled: false,
        defaultResponseTimeout: _responseTimeout,
        defaultWriteTimeout: _responseTimeout,
      );
      try {
        await _connectImap(client, host);
      } catch (error) {
        connectionErrors.add('$host: $error');
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

    throw MailConnectionException(
      'Could not reach a secure IMAP server. ${connectionErrors.join('; ')}',
    );
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
