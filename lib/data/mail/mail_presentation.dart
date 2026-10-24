String displaySenderName({
  required String? personalName,
  required String? email,
  required String fallback,
}) {
  var name = personalName?.trim();
  if (name != null && name.length > 1) {
    final matchingQuotes = (name.startsWith('"') && name.endsWith('"')) ||
        (name.startsWith("'") && name.endsWith("'"));
    if (matchingQuotes) name = name.substring(1, name.length - 1).trim();
  }
  if (name != null && name.isNotEmpty) return name.replaceAll(RegExp(r'\s+'), ' ');
  final address = email?.trim();
  return address == null || address.isEmpty ? fallback : address;
}

String formatMailTimestamp(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) return '';
  final sentAt = timestamp.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = sentAt.hour % 12 == 0 ? 12 : sentAt.hour % 12;
  final minute = sentAt.minute.toString().padLeft(2, '0');
  final meridiem = sentAt.hour < 12 ? 'AM' : 'PM';
  return '${sentAt.day} ${months[sentAt.month - 1]} ${sentAt.year}, $hour:$minute $meridiem';
}

/// Turns HTML-only messages into readable text before showing them in the app.
/// Scripts, styles, and markup are removed; remote HTML is never executed.
String htmlMailToText(String html) {
  var text = html
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(
        RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1\s*>', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(p|div|li|tr|h[1-6]|section|article)\s*>', caseSensitive: false),
        '\n',
      )
      .replaceAll(RegExp(r'<[^>]*>'), ' ');

  text = text.replaceAllMapped(
    RegExp(r'&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);', caseSensitive: false),
    (match) {
      final entity = match[1]!.toLowerCase();
      if (entity == 'amp') return '&';
      if (entity == 'lt') return '<';
      if (entity == 'gt') return '>';
      if (entity == 'quot') return '"';
      if (entity == 'apos' || entity == '#39') return "'";
      if (entity == 'nbsp') return ' ';
      final radix = entity.startsWith('#x') ? 16 : 10;
      final digits = entity.startsWith('#x') ? entity.substring(2) : entity.substring(1);
      final codePoint = int.tryParse(digits, radix: radix);
      if (codePoint == null || codePoint < 0 || codePoint > 0x10ffff) {
        return match[0]!;
      }
      return String.fromCharCode(codePoint);
    },
  );

  return text
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}
