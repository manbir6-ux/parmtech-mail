import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/mail/cpanel_mail_service.dart';
import 'package:parm_mail/data/mail/mail_conversations.dart';

MailItem message(String subject, int day, {String id = '', String reply = '',
    String sender = 'alex@example.com', String refs = ''}) => MailItem(
      sender: 'Alex', senderAddress: sender, subject: subject, body: 'Test',
      time: '', sentAt: DateTime.utc(2026, 10, day), unread: true,
      messageId: id, inReplyTo: reply, references: refs,
    );

void main() {
  test('groups reply prefixes for same sender', () {
    final groups = groupMailConversations([
      message('test', 1), message('Re: test', 2),
      message('Fwd: unrelated', 3),
    ]);
    expect(groups.length, 2);
    expect(groups.last.count, 2);
    expect(groups.last.latest.subject, 'Re: test');
  });

  test('uses references across sender changes but not bare subject alone', () {
    final groups = groupMailConversations([
      message('Planning', 1, id: '<first@test>', sender: 'a@example.com'),
      message('Re: Planning', 2, reply: '<first@test>',
          sender: 'b@example.com'),
      message('Planning', 3, sender: 'c@example.com'),
    ]);
    expect(groups.length, 2);
    expect(groups.last.count, 2);
  });

  test('mail cache roundtrips conversation and reply-to metadata', () {
    final original = message('Re: project', 1,
        id: '<second@test>', reply: '<first@test>', refs: '<first@test>');
    final restored = MailItem.fromJson(original.toJson());
    expect(restored.messageId, original.messageId);
    expect(restored.inReplyTo, original.inReplyTo);
    expect(restored.references, original.references);
  });

  test('removes repeated Re/Fwd subject prefixes', () {
    expect(conversationSubject('RE: Fwd:  Hello  World '), 'hello world');
  });
}
