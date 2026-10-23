# Acceptance criteria and current status

- [x] Add a cPanel mailbox with email and password; verify IMAP before saving.
- [x] Try secure host candidates with IMAP 993; for `parmtech.au`, prefer the cPanel URL hostname `premium214.web-hosting.com`, then the domain `parmtech.au`.
- [x] Stop host fallback on authentication failure.
- [x] Fetch recent Inbox messages and compose/send through authenticated SMTP 465.
- [x] List server-provided folders, switch mailbox, and search the messages currently synced.
- [x] Store up to 10 credentials in OS secure storage and restore accounts on restart.
- [x] Request local notification permission only after the user asks; detect unread-mail changes during app-process syncs.
- [x] Remove an account and erase its saved password from secure storage.
- [ ] Add persistent offline cache and complete message flag actions.
- [ ] Add attachments, reply/forward, robust HTML message rendering and background sync.
- [ ] Verify notification behavior independently on current Android and iOS devices; no instant push guarantee is made.
- [ ] Verify email connection and notifications on current Android and iOS devices with real mailbox credentials.
- [ ] Complete store signing, distribution and review. iOS workflow output is unsigned and must be signed before installation or release.
