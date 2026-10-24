import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/accounts/mail_account.dart';
import 'package:parm_mail/data/mail/cpanel_mail_service.dart';

void main() {
  test('all email domains use the same private server for incoming and outgoing', () {
    for (final email in [
      'info@parmtech.au',
      'info@manbirtong.com',
      'support@client-domain.com',
      'test@gmail.com',
      'test@yahoo.com',
    ]) {
      expect(cPanelHostCandidates(email).map((candidate) => candidate.host),
          [parmTechMailServerHost]);
      expect(recommendedSmtpHost(email), parmTechMailServerHost);
    }
    expect(cPanelHostCandidates('not-an-email'), isEmpty);
    expect(recommendedSmtpHost('not-an-email'), isEmpty);
  });

  test('legacy hostnames are overridden upon account restoration', () {
    const oldAccount = MailAccount(
      email: 'info@client-domain.com',
      password: 'private-password',
      imapHost: 'mail.client-domain.com',
      smtpHost: 'smtp.mail.yahoo.com',
      useCustomServer: true,
    );
    final restored = MailAccount.fromJson(oldAccount.toJson());
    expect(restored.imapHost, parmTechMailServerHost);
    expect(restored.smtpHost, parmTechMailServerHost);
    expect(restored.useCustomServer, isFalse);
    expect(restored.email, oldAccount.email);
    expect(restored.password, oldAccount.password);
  });

  test('imported account hostnames are always forced to the private host', () {
    final imported = MailAccount.fromJson({
      'email': 'support@client.com',
      'password': 'not-shared',
      'imapHost': 'attacker.example.org',
      'smtpHost': 'untrusted.example.org',
      'useCustomServer': true,
    });
    expect(imported.imapHost, parmTechMailServerHost);
    expect(imported.smtpHost, parmTechMailServerHost);
    expect(imported.useCustomServer, isFalse);
  });

  test('private mail hint does not suggest other providers', () {
    expect(mailSetupHint('sales@example.com'), contains('Private ParmTech'));
    expect(mailSetupHint('sales@example.com'), contains('Only mailboxes'));
  });

  test('TLS failures still surface to the user', () {
    const message = 'Could not connect to IMAP securely. '
        'Tried: premium214.web-hosting.com:993 '
        '(TLS certificate or handshake failed).';
    expect(friendlyMailError(const MailConnectionException(message)), message);
  });

  test('mailbox identity uses the normalized full email address', () {
    const account = MailAccount(
      email: ' Info@ParmTech.au ',
      password: 'never-log-this',
      imapHost: parmTechMailServerHost,
      smtpHost: parmTechMailServerHost,
    );
    expect(account.id, 'info@parmtech.au');
  });

  test('mail addresses reject malformed domains before connecting', () {
    expect(isValidMailAddress('info@parmtech.au'), isTrue);
    expect(isValidMailAddress(' sales+au@parmtech.au '), isTrue);
    expect(isValidMailAddress('info@@parmtech.au'), isFalse);
    expect(isValidMailAddress('info@parmtech'), isFalse);
    expect(isValidMailAddress('info@-parmtech.au'), isFalse);
    expect(isValidMailAddress('info@parmtech..au'), isFalse);
    expect(isValidMailAddress(''), isFalse);
  });
}
