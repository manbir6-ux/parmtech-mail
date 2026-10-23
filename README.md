# ParmTech Mail

Premium, cross-platform email client for cPanel/Namecheap mailboxes, built with Flutter. The project targets Android, iOS, Windows, macOS and Linux from one codebase.

## Current implementation

- Dark premium inbox and responsive onboarding / compose UI.
- IMAP over validated TLS (993), secure host fallback, inbox fetch and SMTP send over TLS (465).
- Email + password account setup, with a maximum of 10 accounts.
- Server-reported folders with Spam/Junk alias de-duplication, compact inbox rows with sender names and dates, local inbox search, explicit account removal and foreground sync alerts.
- HTML-only messages are converted to safe readable text; email markup and remote content are not executed.
- Android background unread checks use WorkManager while the app is backgrounded, require a network connection and run no more frequently than Android permits. iOS and desktop background timing is controlled by each operating system; IMAP polling is not instant push.
- Passwords stored only in OS-backed secure storage; Android backup is disabled to prevent restoring encrypted credentials without their device key. There is no ParmTech credential server.
- For `parmtech.au`, IMAP tries the supplied cPanel server `premium214.web-hosting.com` first, then the domain shown in cPanel, `parmtech.au`. It does not guess a `mail.` hostname. A host fallback is attempted for connection errors only; authentication failures stop immediately.
- CI runs analysis, Flutter tests, Android preparation tests, and release builds for Android, iOS (unsigned), Windows, macOS DMG and Linux on main-branch pushes.

This is an early development build, not a store-ready release. Reply/forward, attachments, offline cache, full HTML rendering and server-based push notifications remain in later milestones. Android may defer scheduled checks because of battery settings, and IMAP polling cannot guarantee instant notifications on shared hosting.

## Requirements and run

Use Flutter 3.47+ (Dart 3.13+). On Linux, install Flutter desktop build prerequisites and `libsecret-1-0` / `libsecret-1-dev`; keep a Secret Service keyring available when running the app. On macOS install Xcode; on Windows install Visual Studio with Desktop development with C++.

```sh
flutter create . --platforms=android,ios,windows,macos,linux
python3 tool/prepare_android.py
python3 tool/prepare_ios.py
python3 tool/prepare_macos.py
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
