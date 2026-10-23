# Acceptance criteria and current status

- [x] Add a cPanel mailbox with email and password; verify IMAP before saving.
- [x] Try secure host candidates with IMAP 993; for `parmtech.au`, prefer the domain then `premium214.web-hosting.com` then `mail.parmtech.au`.
- [x] Stop host fallback on authentication failure.
- [x] Fetch recent Inbox messages and compose/send through authenticated SMTP 465.
- [x] List server-provided folders, switch mailbox, and search the messages currently synced.
- [x] Store up to 10 credentials in OS secure storage and restore accounts on restart.
- [x] Request local notification permission and notify about newly detected unread mail during a later foreground sync.
- [x] Remove an account and erase its saved password from secure storage.
- [ ] Add persistent offline cache and complete message flag actions.
- [ ] Add attachments, reply/forward, robust HTML message rendering and background sync.
- [ ] Verify notification behavior independently on current Android and iOS devices; no instant push guarantee is made.
- [ ] Complete current Flutter CI, platform builds, device tests, signing and store review.
