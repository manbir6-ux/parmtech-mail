import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mail_account.dart';

class SecureAccountVault {
  SecureAccountVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Avoid macOS Keychain Sharing entitlements and provisioning;
              // standard Keychain still protects credentials on this device.
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  static const int maxAccounts = 10;
  static const String _storageKey = 'parm_mail.accounts.v1';
  static const String _unreadCountsKey = 'parm_mail.unread_counts.v1';
  static const String _mailCachePrefix = 'parm_mail.cache.';
  final FlutterSecureStorage _storage;

  Future<List<MailAccount>> readAll() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => MailAccount.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> add(MailAccount account) async {
    final accounts = (await readAll()).toList();
    final existing = accounts.indexWhere((item) => item.id == account.id);
    if (existing < 0 && accounts.length >= maxAccounts) {
      throw const AccountLimitReachedException();
    }
    if (existing < 0) {
      accounts.add(account);
    } else {
      accounts[existing] = account;
    }
    await _write(accounts);
  }

  Future<void> replaceAll(List<MailAccount> accounts) async {
    final ids = accounts.map((account) => account.id).toSet();
    if (accounts.length > maxAccounts || ids.length != accounts.length) {
      throw const AccountLimitReachedException();
    }
    await _write(accounts);
  }

  Future<void> remove(String email) async {
    final id = email.trim().toLowerCase();
    final accounts = (await readAll()).where((item) => item.id != id).toList();
    // Cached message bodies are private too. Removing the login must not
    // leave another account's cached messages readable on this device.
    await _deleteMailCaches(id);
    await _write(accounts);
    final unreadCounts = await readUnreadCounts();
    unreadCounts.remove(id);
    await writeUnreadCounts(unreadCounts);
  }

  Future<Map<String, int>> readUnreadCounts() async {
    final raw = await _storage.read(key: _unreadCountsKey);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String, int>{};
      return decoded.map((key, value) {
        final count = value is int ? value : int.tryParse('$value') ?? 0;
        return MapEntry(key, count < 0 ? 0 : count);
      });
    } on FormatException {
      return <String, int>{};
    }
  }

  Future<void> writeUnreadCounts(Map<String, int> counts) => _storage.write(
        key: _unreadCountsKey,
        value: jsonEncode(counts),
      );

  Future<String?> readMailCache(String accountId, String folder) =>
      _storage.read(key: _cacheKey(accountId, folder));

  Future<void> writeMailCache(String accountId, String folder, String value) =>
      _storage.write(key: _cacheKey(accountId, folder), value: value);

  String _cacheKey(String accountId, String folder) =>
      '${_accountCachePrefix(accountId)}${Uri.encodeComponent(folder)}';

  String _accountCachePrefix(String accountId) =>
      '$_mailCachePrefix${Uri.encodeComponent(accountId)}.';

  /// Includes every locally cached folder for this account, not only folders
  /// currently displayed in the active account's UI. Used for full exports.
  Future<Map<String, String>> readMailCaches(String accountId) async {
    final prefix = _accountCachePrefix(accountId);
    final stored = await _storage.readAll();
    return {
      for (final entry in stored.entries)
        if (entry.key.startsWith(prefix))
          Uri.decodeComponent(entry.key.substring(prefix.length)): entry.value,
    };
  }

  Future<void> _deleteMailCaches(String accountId) async {
    final prefix = _accountCachePrefix(accountId);
    final keys = (await _storage.readAll()).keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }

  /// Erase only ParmTech Mail's own account, cache and unread-count records.
  /// Do not delete other unrelated secure-storage keys.
  Future<void> clear() async {
    final keys = (await _storage.readAll()).keys
        .where((key) =>
            key == _storageKey ||
            key == _unreadCountsKey ||
            key.startsWith(_mailCachePrefix))
        .toList(growable: false);
    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }

  Future<void> _write(List<MailAccount> accounts) => _storage.write(
        key: _storageKey,
        value: jsonEncode(accounts.map((account) => account.toJson()).toList()),
      );
}

class AccountLimitReachedException implements Exception {
  const AccountLimitReachedException();

  @override
  String toString() => 'A maximum of ${SecureAccountVault.maxAccounts} accounts is allowed.';
}
