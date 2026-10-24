import 'cpanel_mail_service.dart';

String conversationSubject(String subject) {
  var clean = subject.trim();
  final prefixes = RegExp(r'^(?:(?:re|fw|fwd)\s*:\s*)+', caseSensitive: false);
  clean = clean.replaceFirst(prefixes, '').trim();
  return clean.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

class MailConversation {
  const MailConversation(this.messages);
  final List<MailItem> messages;
  MailItem get latest => messages.last;
  bool get unread => messages.any((message) => message.unread);
  int get count => messages.length;
  String get identity => latest.identity;
}

/// Link messages with RFC references; fall back only to same sender + subject.
List<MailConversation> groupMailConversations(Iterable<MailItem> source) {
  final items = source.toList()
    ..sort((a, b) {
      final left = a.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });
  final groups = <List<MailItem>>[];
  final indexedIds = <String, int>{};
  final subjectSender = <String, int>{};
  for (final item in items) {
    final subject = conversationSubject(item.subject);
    final sender = item.senderAddress.trim().toLowerCase();
    final fallback = '$subject|$sender';
    final replyIds = RegExp(r'<[^<>]+>')
        .allMatches('${item.inReplyTo} ${item.references}')
        .map((match) => match.group(0)!.toLowerCase())
        .toList();
    final normalizedReplyId = item.inReplyTo.trim().toLowerCase();
    if (replyIds.isEmpty && normalizedReplyId.isNotEmpty) {
      replyIds.add(normalizedReplyId);
    }
    int? index;
    for (final id in replyIds) {
      index = indexedIds[id];
      if (index != null) break;
    }
    if (index == null && subject.isNotEmpty && sender.isNotEmpty) {
      index = subjectSender[fallback];
    }
    index ??= groups.length;
    if (index == groups.length) groups.add([]);
    groups[index].add(item);
    if (item.messageId.trim().isNotEmpty) {
      indexedIds[item.messageId.trim().toLowerCase()] = index;
    }
    if (subject.isNotEmpty && sender.isNotEmpty) {
      subjectSender[fallback] = index;
    }
  }
  return groups.map((items) => MailConversation(items)).toList()
    ..sort((a, b) {
      final left = a.latest.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.latest.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
}
