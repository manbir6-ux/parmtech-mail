import 'package:flutter_test/flutter_test.dart';
import 'package:parm_mail/data/mail/mail_fetch_guard.dart';

void main() {
  test('empty IMAP folder never issues FETCH', () async {
    var calls = 0;
    final result = await guardedImapFetch<List<int>>(
      selectAndCount: () async => 0,
      fetch: () async { calls++; return [1]; },
      empty: () => [],
    );
    expect(result, isEmpty);
    expect(calls, 0);
  });

  test('invalid messageset caused by concurrent server deletion is retried', () async {
    var selected = 0, fetched = 0;
    final result = await guardedImapFetch<List<int>>(
      selectAndCount: () async {
        selected++;
        return selected == 1 ? 8 : 0;
      },
      fetch: () async {
        fetched++;
        throw StateError('BAD Error in IMAP command FETCH: Invalid messageset');
      },
      empty: () => [],
    );
    expect(result, isEmpty);
    expect(selected, 2);
    expect(fetched, 1);
  });

  test('failed login or network errors never clear the local cache', () async {
    await expectLater(
      guardedImapFetch<List<int>>(
        selectAndCount: () async => 8,
        fetch: () async => throw StateError('TLS handshake failed'),
        empty: () => [],
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('persistent invalid IMAP sequence errors are surfaced after one retry', () async {
    var calls = 0;
    await expectLater(
      guardedImapFetch<List<int>>(
        selectAndCount: () async => 2,
        fetch: () async {
          calls++;
          throw StateError('Invalid messageset');
        },
        empty: () => [],
      ),
      throwsA(isA<StateError>()),
    );
    expect(calls, 2);
  });

  test('stale and legacy UID-less messages can be removed from cache', () {
    expect(shouldRemoveLocallyAfterDelete(
        hasValidUid: false, uidStillExists: false), isTrue);
    expect(shouldRemoveLocallyAfterDelete(
        hasValidUid: true, uidStillExists: false), isTrue);
    expect(shouldRemoveLocallyAfterDelete(
        hasValidUid: true, uidStillExists: true), isFalse);
  });
}
