# ParmTech Mail

Premium, cross-platform email client for cPanel/Namecheap mailboxes, built with Flutter. The project targets Android, iOS, Windows, macOS and Linux from one codebase.

## Current implementation

- Dark premium inbox and responsive onboarding / compose UI.
- IMAP over validated TLS (993), secure host fallback, inbox fetch and SMTP send over TLS (465).
- Email + password account setup, with a maximum of 10 accounts.
- Passwords stored only in OS-backed secure storage; there is no ParmTech credential server.
- For `parmtech.au`, IMAP tries `parmtech.au`, then the supplied cPanel host `premium214.web-hosting.com`, then `mail.parmtech.au`. A host fallback is attempted for connection errors only; authentication failures stop immediately.
- CI checks and a manual/tagged build workflow for Android, iOS, Windows, macOS DMG and Linux.

This is an early development build, not a store-ready release. Mailbox folders beyond Inbox, offline cache, attachments, background sync and push notification delivery remain in later milestones. IMAP polling cannot guarantee instant notifications on shared hosting.

## Requirements and run

Install current stable Flutter (Dart 3.10+). On Linux, install Flutter desktop build prerequisites and `libsecret-1-0` / `libsecret-1-dev`; on macOS install Xcode; on Windows install Visual Studio with Desktop development with C++.

```sh
flutter create . --platforms=android,ios,windows,macos,linux
flutter pub get
flutter run
```

## Build locally

```sh
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
flutter build linux --release
flutter build macos --release
flutter build ios --release --no-codesign
```

For iPhone installation/App Store distribution, an Apple Developer signing identity and provisioning profile are still required. GitHub Actions can build unsigned artifacts; release signing must be configured privately in repository secrets.

See `docs/architecture.md` and `docs/acceptance.md` for current behavior and release gates.
