/// IMAP sequence numbers are volatile: messages may be expunged while FETCH
/// is in flight. Never request FETCH for an empty mailbox, and retry once
/// using a fresh SELECT when the server reports an invalid message set.
bool isInvalidImapMessageSet(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('invalid messageset') ||
      message.contains('invalid message set');
}

Future<T> guardedImapFetch<T>({
  required Future<int> Function() selectAndCount,
  required Future<T> Function() fetch,
  required T Function() empty,
}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    final existing = await selectAndCount();
    if (existing <= 0) return empty();
    try {
      return await fetch();
    } catch (error) {
      if (!isInvalidImapMessageSet(error) || attempt == 1) rethrow;
    }
  }
  return empty();
}

/// A UID which no longer exists is already deleted on the server.
/// Treat that operation as a successful local reconciliation, not as
/// a request to delete another message or as a permanent sync failure.
bool shouldRemoveLocallyAfterDelete({
  required bool hasValidUid,
  required bool uidStillExists,
}) => !hasValidUid || !uidStillExists;
