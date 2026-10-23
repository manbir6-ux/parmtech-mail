import 'package:enough_mail/enough_mail.dart' as mail;

import '../accounts/mail_account.dart' as model;

class MailItem {
  const MailItem({
    required this.sender,
    required this.subject,
    required this.body,
    required this.time,
    required this.unread,
  });
  final String sender;
  final String subject;
  final String body;
  final String time;
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
/// authentication rejection is returned immediately so a bad password is not
/// retried against unrelated endpoints.
class CpanelMailService {
  Future<model.MailAccount> verify(model.MailAccount account) async {
    final connectionErrors = <String>[];
    for (final candidate in model.cPanelHostCandidates(account.email)) {
      final client = mail.ImapClient(isLogEnabled: false);
      try {
        await client.connectToServer(
          candidate.host,
          model.MailAccount.imapPort,
          isSecure: true,
        );
      } catch (error) {
        connectionErrors.add('${candidate.host}: $error');
        continue;
      }
      try {
        await client.login(account.email.trim(), account.password);
        await client.selectInbox();
        await client.logout();
        return model.MailAccount(
          email: account.email.trim(),
          password: account.password,
          imapHost: candidate.host,
          smtpHost: candidate.host,
          displayName: account.displayName,
        );
      } catch (_) {
        rethrow;
      }
    }
    throw MailConnectionException(
      'Could not reach a secure IMAP server. ${connectionErrors.join('; ')}',
    );
  }

  Future<List<MailFolder>> listFolders(model.MailAccount account) async {
    final client = mail.ImapClient(isLogEnabled: false);
    await client.connectToServer(
      account.imapHost,
      model.MailAccount.imapPort,
      isSecure: true,
    );
    try {
      await client.login(account.email, account.password);
      final boxes = await client.listMailboxes(recursive: true);
      return boxes
          .map(
            (box) => MailFolder(
              name: box.encodedName,
              path: box.encodedPath,
              unread: box.messagesUnseen,
            ),
          )
          .toList(growable: false);
    } finally {
      await client.logout();
    }
  }

  Future<List<MailItem>> fetchInbox(
    model.MailAccount account, {
    int count = 40,
  }) => fetchFolder(account, 'INBOX', count: count);

  Future<List<MailItem>> fetchFolder(
    model.MailAccount account,
    String folderPath, {
    int count = 40,
  }) async {
    final client = mail.ImapClient(isLogEnabled: false);
    await client.connectToServer(
      account.imapHost,
      model.MailAccount.imapPort,
      isSecure: true,
    );
    try {
      await client.login(account.email, account.password);
      if (folderPath.toUpperCase() == 'INBOX') {
        await client.selectInbox();
      } else {
        await client.selectMailboxByPath(folderPath);
      }
      final result = await client.fetchRecentMessages(
        messageCount: count,
        criteria: 'BODY.PEEK[]',
      );
      return result.messages.reversed
          .map((message) {
            final body = message.decodeTextPlainPart() ?? '';
            final sender = message.from?.toString() ?? account.email;
            final subject = message.decodeSubject()?.trim();
            return MailItem(
              sender: sender,
              subject: subject == null || subject.isEmpty
                  ? '(no subject)'
                  : subject,
              body: body.trim(),
              time: '',
              unread: !message.isSeen,
            );
          })
          .toList(growable: false);
    } finally {
      await client.logout();
    }
  }

  Future<void> send(
    model.MailAccount account, {
    required String to,
    required String subject,
    required String body,
  }) async {
    final candidates = <String>{
      account.smtpHost,
      ...model.cPanelHostCandidates(account.email).map((e) => e.host),
    };
    Object? lastConnectionError;
    for (final host in candidates) {
      final client = mail.SmtpClient(host, isLogEnabled: false);
      try {
        await client.connectToServer(
          host,
          model.MailAccount.smtpPort,
          isSecure: true,
        );
      } catch (error) {
        lastConnectionError = error;
        continue;
      }
      try {
        await client.ehlo();
        if (client.serverInfo.supportsAuth(mail.AuthMechanism.plain)) {
          await client.authenticate(
            account.email,
            account.password,
            mail.AuthMechanism.plain,
          );
        } else if (client.serverInfo.supportsAuth(mail.AuthMechanism.login)) {
          await client.authenticate(
            account.email,
            account.password,
            mail.AuthMechanism.login,
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
              ..from = [mail.MailAddress('', account.email)]
              ..to = [mail.MailAddress('', to)]
              ..subject = subject;
        final response = await client.sendMessage(message.buildMimeMessage());
        if (!response.isOkStatus) {
          throw const MailConnectionException(
            'The outgoing server rejected the message.',
          );
        }
        await client.quit();
        return;
      } catch (_) {
        rethrow;
      }
    }
    throw MailConnectionException(
      'Could not reach a secure SMTP server. ${lastConnectionError ?? ''}',
    );
  }

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

class MailConnectionException implements Exception {
  const MailConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

String friendlyMailError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  if (text.toLowerCase().contains('auth') ||
      text.toLowerCase().contains('login')) {
    return 'Email or password was rejected. Check the mailbox password in cPanel.';
  }
  if (text.toLowerCase().contains('certificate') ||
      text.toLowerCase().contains('handshake')) {
    return 'Secure TLS connection failed. Check the server certificate and hostname.';
  }
  return text;
}
