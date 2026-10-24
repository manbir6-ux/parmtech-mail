import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/appearance/mail_appearance.dart';
import 'package:parm_mail/widgets/mail_settings_page.dart';

void main() {
  testWidgets('Settings includes accounts, backup, themes, fonts and layouts',
      (tester) async {
    MailAppearance prefs = const MailAppearance();
    await tester.pumpWidget(MaterialApp(
      home: MailSettingsPage(
        appearance: prefs,
        onAppearanceChanged: (value) => prefs = value,
        accountEmails: const ['hello@example.com'],
        onAddAccount: () async {},
        onRemoveAccount: (_) async {},
        onExportBackup: () async {},
        onImportBackup: () async {},
      ),
    ));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Enable new-mail alerts'), findsNothing);
    expect(find.text('Fast background mail sync'), findsNothing);
    expect(find.byType(Switch), findsNothing);

    final darkTheme = find.byKey(const Key('palette-midnight'));
    await tester.ensureVisible(darkTheme);
    await tester.pumpAndSettle();
    await tester.tap(darkTheme);
    await tester.pumpAndSettle();
    expect(prefs.palette, MailPalette.midnight);

    // Appearance options make the settings list taller. Lazy list children
    // only exist after scrolling, so find the lower settings deliberately.
    await tester.scrollUntilVisible(find.text('Connect another account'), 240);
    expect(find.text('Connect another account'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Export encrypted backup'), 240);
    expect(find.text('Export encrypted backup'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Import backup'), 200);
    expect(find.text('Import backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
