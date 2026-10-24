import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/backup/encrypted_mail_backup.dart';

void main() {
  test('rejects empty or oversized backup before key derivation', () async {
    await expectLater(
      EncryptedMailBackup.decrypt([], 'long backup password'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      EncryptedMailBackup.decrypt(
        Uint8List(EncryptedMailBackup.maxBackupBytes + 1),
        'long backup password',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('encrypted backups round-trip and reject a wrong passphrase', () async {
    final original = <String, Object?>{
      'accounts': [{'email': 'hello@example.com', 'password': 'secret'}],
      'mailCache': {'hello@example.com': {'INBOX': []}},
    };
    final encrypted = await EncryptedMailBackup.encrypt(original, 'a long backup phrase');
    expect(String.fromCharCodes(encrypted), isNot(contains('secret')));
    expect(await EncryptedMailBackup.decrypt(encrypted, 'a long backup phrase'), original);
    await expectLater(EncryptedMailBackup.decrypt(encrypted, 'not the right phrase'), throwsA(anything));
  });
}
