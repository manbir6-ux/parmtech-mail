import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/mail/cpanel_mail_service.dart';
import 'package:parm_mail/data/mail/mail_presentation.dart';
import 'package:parm_mail/main.dart';

void main() {
  group('mail presentation', () {
    test('shows a sender name instead of a raw address-list representation', () {
      expect(
        displaySenderName(
          personalName: '  "Fiverr"  ',
          email: 'noreply@example.com',
          fallback: 'info@example.com',
        ),
        'Fiverr',
      );
      expect(
        displaySenderName(
          personalName: '  ',
          email: 'noreply@example.com',
          fallback: 'info@example.com',
        ),
        'noreply@example.com',
      );
    });

    test('always shows the calendar date and time', () {
      final now = DateTime(2026, 10, 23, 10, 17);
      expect(
        formatMailTimestamp(DateTime(2026, 10, 23, 9, 5), now: now),
        '23 Oct 2026, 9:05 AM',
      );
      expect(
        formatMailTimestamp(DateTime(2026, 10, 22, 18, 0), now: now),
        '22 Oct 2026, 6:00 PM',
      );
      expect(formatMailTimestamp(null, now: now), isEmpty);
    });

    test('renders HTML-only email content as safe readable text', () {
      expect(
        htmlMailToText(
          '<style>.hide { display:none }</style>'
          '<p>Hello&nbsp;Manbir &amp; team</p>'
          '<script>alert("x")</script><p>Order &#35;42</p>',
        ),
        'Hello Manbir & team\nOrder #42',
      );
    });

    test('collapses Spam/Junk aliases and keeps the folder with unread mail', () {
      final folders = deduplicateMailFolders([
        const MailFolder(name: 'INBOX.spam', path: 'INBOX.spam', unread: 0),
        const MailFolder(name: 'Junk', path: 'Junk', unread: 3),
        const MailFolder(name: 'Sent Items', path: 'INBOX.Sent', unread: 0),
        const MailFolder(name: 'Sent', path: 'Sent', unread: 1),
      ]);

      expect(folders, hasLength(2));
      expect(folders.first.path, 'Junk');
      expect(folders.first.unread, 3);
    });
  });

  testWidgets('long email content is scrollable on the message screen', (
    tester,
  ) async {
    final body = List.filled(400, 'A readable email sentence.').join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: MailDetailPage(
          message: MailItem(
            sender: 'Fiverr',
            senderAddress: 'noreply@example.com',
            subject: 'Your order is confirmed',
            body: body,
            time: '9:05 AM',
            sentAt: DateTime(2026, 10, 23, 9, 5),
            unread: true,
          ),
        ),
      ),
    );

    expect(find.text('Your order is confirmed'), findsOneWidget);
    expect(find.text('noreply@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
