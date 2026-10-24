import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// All palettes are local/offline and can be used without signing in.
enum MailPalette {
  pearl('Pearl', false, Color(0xFFF5F6FC), Color(0xFFFFFFFF), Color(0xFF5263DC)),
  frost('Frost', false, Color(0xFFEAF6FB), Color(0xFFFFFFFF), Color(0xFF007F9C)),
  sand('Sand', false, Color(0xFFFCF3EA), Color(0xFFFFFCF6), Color(0xFFA96335)),
  midnight('Midnight', true, Color(0xFF10182B), Color(0xFF1A2640), Color(0xFF899DFF)),
  graphite('Graphite', true, Color(0xFF16191D), Color(0xFF252B31), Color(0xFF94D2BA)),
  nebula('Nebula', true, Color(0xFF1C1634), Color(0xFF2B224A), Color(0xFFC4A1FF));

  const MailPalette(this.label, this.isDark, this.background, this.surface, this.accent);

  final String label;
  final bool isDark;
  final Color background;
  final Color surface;
  final Color accent;
}

/// Six offline system font families. Android supports these named families;
/// other platforms automatically substitute their closest installed face.
enum MailFont {
  modern('Modern', 'sans-serif'),
  bold('Bold', 'sans-serif-medium'),
  condensed('Condensed', 'sans-serif-condensed'),
  airy('Airy', 'sans-serif-light'),
  editorial('Editorial', 'serif'),
  mono('Mono', 'monospace');

  const MailFont(this.label, this.family);
  final String label;
  final String family;
}

enum MailLayout {
  comfortable('Comfort', 'Spacious rows with previews'),
  compact('Compact', 'More messages on screen'),
  cards('Cards', 'Separated, readable cards');

  const MailLayout(this.label, this.description);
  final String label;
  final String description;
}

class MailAppearance {
  const MailAppearance({
    this.palette = MailPalette.pearl,
    this.font = MailFont.modern,
    this.layout = MailLayout.comfortable,
  });

  final MailPalette palette;
  final MailFont font;
  final MailLayout layout;

  MailAppearance copyWith({MailPalette? palette, MailFont? font, MailLayout? layout}) =>
      MailAppearance(
        palette: palette ?? this.palette,
        font: font ?? this.font,
        layout: layout ?? this.layout,
      );

  Map<String, String> toJson() => {
    'palette': palette.name,
    'font': font.name,
    'layout': layout.name,
  };

  factory MailAppearance.fromJson(Map<String, dynamic> json) {
    T option<T extends Enum>(List<T> values, Object? name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }
    return MailAppearance(
      palette: option(MailPalette.values, json['palette'], MailPalette.pearl),
      font: option(MailFont.values, json['font'], MailFont.modern),
      layout: option(MailLayout.values, json['layout'], MailLayout.comfortable),
    );
  }
}

class MailAppearanceStore {
  MailAppearanceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'parm_mail.appearance.v1';
  final FlutterSecureStorage _storage;

  Future<MailAppearance> load() async {
    try {
      final text = await _storage.read(key: _key);
      if (text == null || text.isEmpty) return const MailAppearance();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return MailAppearance.fromJson(decoded);
      }
    } catch (_) {
      // Corrupted/legacy appearance settings should never block access to mail.
    }
    return const MailAppearance();
  }

  Future<void> save(MailAppearance value) =>
      _storage.write(key: _key, value: jsonEncode(value.toJson()));
}
