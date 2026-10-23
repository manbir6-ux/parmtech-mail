# Architecture

## Cross-platform choice

Flutter gives Android and iOS one shared product codebase. Keep platform-specific work behind small adapters for secure storage, background scheduling, notifications, and attachments.

## Account setup

1. User enters email and mailbox password.
2. Derive the domain and probe common secure IMAP/SMTP endpoints, preferring the Namecheap/cPanel server details available to the app.
3. For the supplied cPanel account, attempt `parmtech.au` first and `premium214.web-hosting.com` second; ports IMAP 993 and SMTP 465, implicit TLS.
4. Authenticate against IMAP and SMTP. Never weaken TLS or accept invalid certificates to make a connection succeed.
5. Store credentials in iOS Keychain / Android Keystore-backed secure storage; persist only account metadata elsewhere.
6. Keep sessions until explicit account removal, password change, or server-side rejection. Provide re-authentication for rejected credentials.

## Mailbox and notifications

Use IMAP for folders, message flags, and synchronization; SMTP for sending. Cache message metadata and bodies locally with a clear account-removal cleanup path. Use platform background tasks for periodic sync. A true immediate push alert requires a push-capable server-side watcher or provider support; do not promise instant notifications from IMAP polling alone.

## Security boundaries

- Never send mailbox passwords to a ParmTech backend.
- Keep secrets out of logs, analytics, crash reports, and notification text by default.
- Validate TLS certificates and hostnames.
- Use least-privilege platform permissions and make notification permission opt-in.
- Make logout/remove delete local secrets and cached account data.

## Implemented transport

`CpanelMailService` uses the `enough_mail` Dart IMAP/SMTP client directly from the device. It connects with implicit TLS and standard ports (IMAP 993 / SMTP 465). Host candidates are tried only when the socket/TLS connection fails; the first successful IMAP login is stored in the secure vault. An authentication error is not treated as a server-name problem. Message bodies and credentials are not sent to a ParmTech server.

Foreground sync can raise a local notification after a later sync detects a higher unread count. This is not background delivery: shared-hosting IMAP has no generic push guarantee, and this build does not run a server-side watcher.

## Suggested next modules

- `features/accounts`: account list, onboarding, secure account store.
- `features/mail`: inbox, folders, message detail, composer, search.
- `data/imap`: connection discovery, IMAP client adapter, synchronization.
- `data/smtp`: authenticated SMTP transport.
- `platform`: secure storage, notifications, background work, attachment access.
