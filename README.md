# ParmTech Mail

Private, cross-platform mail client for ParmTech-hosted cPanel mailboxes, built with Flutter. Every account authenticates against the same trusted mail server; accounts hosted elsewhere cannot connect. The project targets Android, iOS, Windows, macOS and Linux from one codebase.

## Current implementation

- Dark/light premium inbox, responsive desktop split-pane layout, scrollable mobile folders, single private IMAP/SMTP server and multiple-file compose.
- Six saved visual palettes (Pearl, Frost, Sand, Midnight, Graphite, Nebula), three light and three dark; six device-offline font styles; and three responsive inbox layouts (Comfort, Compact, Cards). Appearance is stored on-device and can be changed from Settings.
- Secure IMAP (993) and SMTP (465) use only `premium214.web-hosting.com` for every email domain. TLS certificate validation is mandatory and has no insecure bypass. A mailbox must exist and authenticate successfully on that private server.
- Email + password account setup, with a maximum of 10 accounts.
- Server-reported folders with Spam/Junk alias de-duplication, custom folder creation, local inbox search, explicit account removal and foreground sync alerts.
- Swipe right to mark read, swipe left to delete, and long-press for selection, sender cleanup, spam, archive, starring and read-state actions. Destructive bulk and sender cleanup operations require confirmation. Message view includes reply, forward, move, print, sender and full date/time details.
- Recently fetched folders are cached in OS-backed encrypted storage for offline reading. Export/import creates a passphrase-encrypted `.ptmail` backup of all saved accounts and their cached folders, including accounts that are not currently selected. Removing an account also removes its cached emails.
- HTML-only messages are converted to safe readable text; email markup and remote content are not executed.
- Android background unread checks use WorkManager while the app is backgrounded, require a network connection and run no more frequently than Android permits. iOS and desktop background timing is controlled by each operating system; IMAP polling is not instant push.
- Passwords stored only in OS-backed secure storage; Android backup is disabled to prevent restoring encrypted credentials without their device key. There is no ParmTech credential server.
- `parmtech.au`, `manbirtong.com`, and every other private client address use the identical server. No SMTP/IMAP hostname entry is exposed in the login UI, no cross-provider fallback is attempted, and restored legacy account settings cannot override this restriction.
- CI runs analysis, Flutter tests, Android preparation tests, and release builds for Android, iOS (unsigned), Windows, macOS DMG and Linux on main-branch pushes.

This is an early development build, not a store-ready release. The composer supports sending attachments up to 20 MB combined; downloading received attachments, full HTML rendering, saved drafts, and server-based push notifications remain later milestones. UI and transport require real-device verification. Android may defer scheduled checks because of battery settings, and IMAP polling cannot guarantee instant notifications on shared hosting.

### Android upgrade signing

To make future APKs install as in-place upgrades, configure these repository Actions secrets once: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`. The workflow uses that same private keystore for every release. Without those secrets GitHub Actions uses a temporary runner debug key; APKs from separate runs will have different signatures. The first release signed with the permanent key must replace the current debug-signed install once (uninstalling the old app removes its local data, so export a backup first).

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

## CI artifacts

The `ParmTech Mail APK and Appetize builds` GitHub Actions workflow checks Flutter analysis/tests, builds an Android release APK, and then produces an unsigned iOS Simulator `.app` inside a ZIP for Appetize.io. Android Appetize accepts APK directly; iOS requires a simulator `.app` ZIP, not an IPA. GitHub Actions artifacts may be ZIP-wrapped downloads, so extract the inner app ZIP before uploading to Appetize. Permanent APK upgrade signing requires four `ANDROID_*` repository secrets; otherwise the default temporary debug key changes between CI runners.

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
