import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/accounts/mail_account.dart';

void main() {
  test('ParmTech cPanel hostname is preferred; domain is fallback', () {
    final parmtech = cPanelHostCandidates('info@parmtech.au');
    expect(parmtech.map((candidate) => candidate.host), [
      'premium214.web-hosting.com',
      'parmtech.au',
    ]);

    final other = cPanelHostCandidates('admin@example.org');
    expect(other.map((candidate) => candidate.host), ['example.org']);
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
}
