import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/appearance/mail_appearance.dart';
import 'package:parm_mail/widgets/mail_settings_page.dart';

void main() {
  test('there are exactly three light and three dark palettes', () {
    expect(MailPalette.values.length, 6);
    expect(MailPalette.values.where((p) => p.isDark).length, 3);
    expect(MailPalette.values.where((p) => !p.isDark).length, 3);
    expect(MailPalette.values.map((p) => p.label).toSet().length, 6);
  });

  test('six distinct offline font families are available', () {
    expect(MailFont.values.length, 6);
    expect(MailFont.values.map((f) => f.family).toSet().length, 6);
  });

  test('there are three actual inbox layouts', () {
    expect(MailLayout.values.length, 3);
    expect(MailLayout.values, contains(MailLayout.compact));
    expect(MailLayout.values, contains(MailLayout.cards));
    expect(MailLayout.values, contains(MailLayout.comfortable));
  });

  test('appearance round trips through local preferences format', () {
    const original = MailAppearance(
      palette: MailPalette.nebula,
      font: MailFont.editorial,
      layout: MailLayout.cards,
    );
    final saved = original.toJson();
    final restored = MailAppearance.fromJson(saved);
    expect(restored.palette, original.palette);
    expect(restored.font, original.font);
    expect(restored.layout, original.layout);
  });

  test('invalid/corrupt preference values use safe defaults', () {
    final restored = MailAppearance.fromJson({
      'palette': 'removed',
      'font': 'unknown',
      'layout': 'unknown',
    });
    expect(restored.palette, MailPalette.pearl);
    expect(restored.font, MailFont.modern);
    expect(restored.layout, MailLayout.comfortable);
  });

  testWidgets('theme font and layout can be changed in Settings', (tester) async {
    MailAppearance chosen = const MailAppearance();
    await tester.pumpWidget(MaterialApp(
      home: MailSettingsPage(
        appearance: chosen,
        onAppearanceChanged: (next) => chosen = next,
        onExportBackup: () async {},
        onImportBackup: () async {},
        onAddAccount: () async {},
        accountEmails: const [],
        onRemoveAccount: (_) async {},
      ),
    ));

    Future<void> choose(String key) async {
      final finder = find.byKey(Key(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await choose('palette-graphite');
    expect(chosen.palette, MailPalette.graphite);

    await choose('font-editorial');
    expect(chosen.font, MailFont.editorial);

    await choose('layout-cards');
    expect(chosen.layout, MailLayout.cards);
  });
}
