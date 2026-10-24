import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/accounts/mail_account.dart';
import 'package:parm_mail/data/accounts/secure_account_vault.dart';

const _first = MailAccount(
  email: 'first@example.com',
  password: 'first-password',
  imapHost: 'example.com',
  smtpHost: 'example.com',
);

const _second = MailAccount(
  email: 'second@example.com',
  password: 'second-password',
  imapHost: 'example.com',
  smtpHost: 'example.com',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('removing an account erases only its own messages and unread count', () async {
    final vault = SecureAccountVault();
    await vault.add(_first);
    await vault.add(_second);
    await vault.writeMailCache(_first.id, 'INBOX', '[{"subject":"private"}]');
    await vault.writeMailCache(_first.id, 'INBOX.Sent', '[{"subject":"sent"}]');
    await vault.writeMailCache(_second.id, 'INBOX', '[{"subject":"keep"}]');
    await vault.writeUnreadCounts({_first.id: 3, _second.id: 1});

    expect(await vault.readMailCaches(_first.id), hasLength(2));
    await vault.remove(_first.email);

    expect((await vault.readAll()).map((account) => account.id), [_second.id]);
    expect(await vault.readMailCaches(_first.id), isEmpty);
    expect(await vault.readMailCache(_first.id, 'INBOX'), isNull);
    expect(await vault.readMailCaches(_second.id), {'INBOX': '[{"subject":"keep"}]'});
    expect(await vault.readUnreadCounts(), {_second.id: 1});
  });

  test('cache export reads every folder across independent accounts', () async {
    final vault = SecureAccountVault();
    await vault.writeMailCache(_first.id, 'INBOX', '[]');
    await vault.writeMailCache(_first.id, 'Drafts', '[1]');
    await vault.writeMailCache(_second.id, 'Archive', '[2]');

    expect(await vault.readMailCaches(_first.id), {'INBOX': '[]', 'Drafts': '[1]'});
    expect(await vault.readMailCaches(_second.id), {'Archive': '[2]'});
  });

  test('similar account names never share cached folders', () async {
    const shortDomain = MailAccount(
      email: 'info@example.com',
      password: 'short-secret',
      imapHost: 'example.com',
      smtpHost: 'example.com',
    );
    const longDomain = MailAccount(
      email: 'info@example.com.au',
      password: 'long-secret',
      imapHost: 'example.com.au',
      smtpHost: 'example.com.au',
    );
    final vault = SecureAccountVault();
    await vault.add(shortDomain);
    await vault.add(longDomain);
    await vault.writeMailCache(shortDomain.id, 'INBOX', '[1]');
    await vault.writeMailCache(longDomain.id, 'INBOX', '[2]');

    expect(await vault.readMailCaches(shortDomain.id), {'INBOX': '[1]'});
    expect(await vault.readMailCaches(longDomain.id), {'INBOX': '[2]'});

    await vault.remove(shortDomain.email);
    expect(await vault.readMailCache(shortDomain.id, 'INBOX'), isNull);
    expect(await vault.readMailCache(longDomain.id, 'INBOX'), '[2]');
  });

  test('clear removes all ParmTech Mail data but preserves unrelated keys', () async {
    const storage = FlutterSecureStorage();
    final vault = SecureAccountVault(storage: storage);
    await vault.add(_first);
    await vault.writeMailCache(_first.id, 'INBOX', '[]');
    await vault.writeUnreadCounts({_first.id: 4});
    await storage.write(key: 'unrelated.application.secret', value: 'keep-me');

    await vault.clear();

    expect(await vault.readAll(), isEmpty);
    expect(await vault.readMailCaches(_first.id), isEmpty);
    expect(await vault.readUnreadCounts(), isEmpty);
    expect(await storage.read(key: 'unrelated.application.secret'), 'keep-me');
  });
}
