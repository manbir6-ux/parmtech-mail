import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/mail/cpanel_mail_service.dart';

void main() {
  test('attachment MIME builder supports filename, binary data and message body', () {
    final builder = mail.MessageBuilder.prepareMultipartMixedMessage()
      ..from = [mail.MailAddress('', 'sender@example.com')]
      ..to = [mail.MailAddress('', 'recipient@example.com')]
      ..subject = 'Attachment example'
      ..addMultipartAlternative(plainText: 'Hello', htmlText: '<p>Hello</p>');

    builder.addBinary(
      Uint8List.fromList([0, 1, 2, 3]),
      mail.MediaType.guessFromFileName('report.pdf'),
      filename: 'report.pdf',
    );
    final outgoing = builder.buildMimeMessage();
    expect(outgoing.renderMessage(), contains('report.pdf'));
    expect(outgoing.decodeSubject(), 'Attachment example');
    expect(outgoing.hasAttachments(), isTrue);
  });

  test('outgoing attachment preserves raw file bytes', () {
    final attachment = OutgoingMailAttachment(
      name: 'hello.txt',
      bytes: Uint8List.fromList([65, 66, 67]),
    );
    expect(attachment.bytes, [65, 66, 67]);
  });
}
