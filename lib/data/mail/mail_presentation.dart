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

/// RFC 3501 INTERNALDATE uses DD-MMM-YYYY HH:MM:SS +HHMM rather
/// than ISO-8601. Fall back to it when a message has no valid Date header.
DateTime? parseImapInternalDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso.toLocal();
  final match = RegExp(
    r'^\s*"?(\d{1,2})-([a-zA-Z]{3})-(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+([+-])(\d{2})(\d{2})"?\s*
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
,
  ).firstMatch(raw);
  if (match == null) return null;
  const months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];
  final month = months.indexOf(match[2]!.toLowerCase()) + 1;
  final day = int.parse(match[1]!);
  final year = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  final offsetHour = int.parse(match[8]!);
  final offsetMinute = int.parse(match[9]!);
  if (month == 0 || day < 1 || day > 31 || hour > 23 ||
      minute > 59 || second > 59 || offsetHour > 23 ||
      offsetMinute > 59) return null;
  final localFields = DateTime.utc(year, month, day, hour, minute, second);
  if (localFields.month != month || localFields.day != day) return null;
  final offset = (offsetHour * 60 + offsetMinute) *
      (match[7] == '+' ? 1 : -1);
  return localFields.subtract(Duration(minutes: offset)).toLocal();
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
