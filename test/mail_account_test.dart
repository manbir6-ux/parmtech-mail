import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/accounts/mail_account.dart';
import 'package:parm_mail/data/mail/cpanel_mail_service.dart';

void main() {
  test('ParmTech cPanel hostname is preferred; domain is fallback', () {
    final parmtech = cPanelHostCandidates('info@parmtech.au');
    expect(parmtech.map((candidate) => candidate.host), [
      'premium214.web-hosting.com',
      'mail.parmtech.au',
      'parmtech.au',
    ]);

    final other = cPanelHostCandidates('admin@example.org');
    expect(other.map((candidate) => candidate.host), ['mail.example.org', 'example.org']);
  });

  test('all owned ParmTech-hosted mail domains share one TLS host', () {
    final owned = [
      cPanelHostCandidates('info@parmtech.au'),
      cPanelHostCandidates('info@manbirtong.com'),
    ];
    for (final hosts in owned) {
      expect(hosts.first.host, 'premium214.web-hosting.com');
    }
    expect(recommendedSmtpHost('info@manbirtong.com'),
        'premium214.web-hosting.com');
  });

  test('saved secure cPanel profile can be reused without copying passwords', () {
    const first = MailAccount(
      email: 'admin@parmtech.au',
      password: 'do-not-copy-password',
      imapHost: 'premium214.web-hosting.com',
      smtpHost: 'premium214.web-hosting.com',
    );
    const second = MailAccount(
      email: 'info@manbirtong.com',
      password: 'unrelated-password',
      imapHost: 'premium214.web-hosting.com',
      smtpHost: 'premium214.web-hosting.com',
    );
    final profiles = reusableMailServers([first, second]);
    expect(profiles.length, 1);
    expect(profiles.single.sourceEmail, 'admin@parmtech.au');
    expect(profiles.single.imapHost, 'premium214.web-hosting.com');
    expect(profiles.single.smtpHost, 'premium214.web-hosting.com');
  });

  test('Yahoo and Gmail use provider SSL/TLS hosts, not the website domain', () {
    expect(cPanelHostCandidates('someone@yahoo.com').single.host,
        'imap.mail.yahoo.com');
    expect(recommendedSmtpHost('someone@yahoo.com'), 'smtp.mail.yahoo.com');
    expect(cPanelHostCandidates('user@gmail.com').single.host,
        'imap.gmail.com');
    expect(recommendedSmtpHost('user@gmail.com'), 'smtp.gmail.com');
    expect(cPanelHostCandidates('admin@other-domain.com').first.host,
        'mail.other-domain.com');
    expect(mailSetupHint('user@yahoo.com'), contains('App Password'));
  });

  test('explicit TLS hostname preference is retained after serialization', () {
    const account = MailAccount(
      email: 'sales@example.org',
      password: 'secret',
      imapHost: 'server123.hosting.example',
      smtpHost: 'server123.hosting.example',
      useCustomServer: true,
    );
    final recovered = MailAccount.fromJson(account.toJson());
    expect(recovered.useCustomServer, isTrue);
    expect(recovered.imapHost, account.imapHost);
    expect(recovered.smtpHost, account.smtpHost);
  });

  test('custom IMAP and SMTP settings require a TLS-capable hostname', () {
    expect(isValidMailServerHost('premium214.web-hosting.com'), isTrue);
    expect(isValidMailServerHost('mail.example.org'), isTrue);
    expect(isValidMailServerHost('https://example.org'), isFalse);
    expect(isValidMailServerHost('example.org:993'), isFalse);
    expect(isValidMailServerHost('invalid host.example.org'), isFalse);
    expect(isValidMailServerHost(''), isFalse);
  });

  test('TLS setup errors are not flattened into generic notifications', () {
    const message = 'Could not connect to IMAP securely. '
        'Tried: mail.example.org:993 (TLS certificate or handshake failed).';
    expect(friendlyMailError(const MailConnectionException(message)), message);
  });

  test('mailbox email is normalized for account identity', () {
    const account = MailAccount(
      email: ' Info@ParmTech.au ',
      password: 'never-log-this',
      imapHost: 'parmtech.au',
      smtpHost: 'parmtech.au',
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
