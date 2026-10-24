import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' as crypto_helpers;

/// Password-protected portable backup. The mailbox password is never written
/// to an unencrypted export file.
class EncryptedMailBackup {
  static const _iterations = 210000;
  static const maxBackupBytes = 64 * 1024 * 1024;

  static Future<Uint8List> encrypt(Map<String, Object?> payload, String passphrase) async {
    if (passphrase.length < 10) {
      throw const FormatException('Use a backup passphrase with at least 10 characters.');
    }
    final salt = crypto_helpers.randomBytes(16);
    final nonce = crypto_helpers.randomBytes(12);
    final key = await _derive(passphrase, salt);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
    );
    final output = Uint8List.fromList(utf8.encode(jsonEncode({
      'format': 'parmtech-mail-backup-v1',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    })));
    if (output.length > maxBackupBytes) {
      throw const FormatException('Backup is too large to export safely.');
    }
    return output;
  }

  static Future<Map<String, dynamic>> decrypt(List<int> fileBytes, String passphrase) async {
    if (fileBytes.isEmpty || fileBytes.length > maxBackupBytes) {
      throw const FormatException('Backup file is empty or too large.');
    }
    final wrapper = jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>;
    if (wrapper['format'] != 'parmtech-mail-backup-v1' || wrapper['iterations'] != _iterations) {
      throw const FormatException('This is not a supported Parmtech Mail backup.');
    }
    final salt = base64Decode(wrapper['salt'] as String);
    final nonce = base64Decode(wrapper['nonce'] as String);
    final tag = base64Decode(wrapper['mac'] as String);
    if (salt.length != 16 || nonce.length != 12 || tag.length != 16) {
      throw const FormatException('Backup encryption metadata is malformed.');
    }
    final key = await _derive(passphrase, salt);
    final box = SecretBox(
      base64Decode(wrapper['cipherText'] as String),
      nonce: nonce,
      mac: Mac(tag),
    );
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  static Future<SecretKey> _derive(String passphrase, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
}
