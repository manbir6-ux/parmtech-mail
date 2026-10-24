import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/widgets/mail_settings_page.dart';

void main() {
  testWidgets('Settings holds account, backup and theme controls',
      (tester) async {
    var changedTheme = false;
    await tester.pumpWidget(MaterialApp(
      home: MailSettingsPage(
        darkTheme: false,
        onThemeToggle: () => changedTheme = !changedTheme,
        accountEmails: const ['hello@example.com'],
        onAddAccount: () async {},
        onRemoveAccount: (_) async {},
        onExportBackup: () async {},
        onImportBackup: () async {},
      ),
    ));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Export encrypted backup'), findsOneWidget);
    expect(find.text('Import backup'), findsOneWidget);
    expect(find.text('Connect another account'), findsOneWidget);
    expect(find.text('Enable new-mail alerts'), findsNothing);
    expect(find.text('Fast background mail sync'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(changedTheme, isTrue);
    expect(tester.takeException(), isNull);
  });
}
