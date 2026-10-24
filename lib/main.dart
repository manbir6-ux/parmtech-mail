import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';
import 'data/background/mail_background_sync.dart';
import 'data/background/live_mail_service.dart';
import 'data/accounts/mail_account.dart';
import 'data/appearance/mail_appearance.dart';
import 'data/accounts/secure_account_vault.dart';
import 'data/backup/encrypted_mail_backup.dart';
import 'data/mail/cpanel_mail_service.dart';
import 'data/mail/mail_conversations.dart';
import 'data/mail/mail_presentation.dart';
import 'widgets/inline_reply_box.dart';
import 'widgets/mail_settings_page.dart';
import 'data/notifications/mail_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) await windowManager.ensureInitialized();
  if (Platform.isAndroid) {
    try {
      await AndroidMailBackgroundSync.initialize();
      await LiveMailService.configure();
    } catch (_) {
      // A scheduler issue should not prevent the mailbox UI from opening.
    }
  }
  runApp(const ParmMailApp());
}

MailAppearance _activeAppearance = const MailAppearance();
bool get _darkTheme => _activeAppearance.palette.isDark;
Color get _panel => _activeAppearance.palette.surface;
const _orange = Color(0xFF5066E9);
const _sky = Color(0xFF08A7C7);
const _muted = Color(0xFF78869B);

ThemeData _mailTheme(Brightness brightness) {
  final palette = _activeAppearance.palette;
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness,
    surface: palette.surface,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    colorScheme: scheme,
    fontFamily: _activeAppearance.font.familyForPlatform(defaultTargetPlatform),
    appBarTheme: AppBarTheme(backgroundColor: palette.background, elevation: 0),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -1.2),
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.6),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.4),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.25),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class ParmMailApp extends StatefulWidget {
  const ParmMailApp({super.key});

  @override
  State<ParmMailApp> createState() => _ParmMailAppState();
}

class _ParmMailAppState extends State<ParmMailApp> {
  final _appearanceStore = MailAppearanceStore();

  @override
  void initState() {
    super.initState();
    unawaited(_restoreAppearance());
  }

  Future<void> _restoreAppearance() async {
    final saved = await _appearanceStore.load();
    if (!mounted) return;
    setState(() => _activeAppearance = saved);
  }

  void _changeAppearance(MailAppearance value) {
    setState(() => _activeAppearance = value);
    unawaited(_appearanceStore.save(value));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ParmTech Mail',
    debugShowCheckedModeBanner: false,
    themeMode: _darkTheme ? ThemeMode.dark : ThemeMode.light,
    theme: _mailTheme(Brightness.light),
    darkTheme: _mailTheme(Brightness.dark),
    home: MailHome(
      appearance: _activeAppearance,
      onAppearanceChanged: _changeAppearance,
    ),
  );
}

class _DesktopSectionLabel extends StatelessWidget {
  const _DesktopSectionLabel(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 11, 14, 7),
    child: Text(value, style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 10, fontWeight: FontWeight.w900,
      letterSpacing: 1.35)),
  );
}

class MailHome extends StatefulWidget {
  const MailHome({
    super.key,
    required this.appearance,
    required this.onAppearanceChanged,
  });

  final MailAppearance appearance;
  final ValueChanged<MailAppearance> onAppearanceChanged;

  @override
  State<MailHome> createState() => _MailHomeState();
}

class _MailHomeState extends State<MailHome>
    with WindowListener, WidgetsBindingObserver {
  final _vault = SecureAccountVault();
  final _service = CpanelMailService();
  final _notifications = MailNotifications();
  List<MailAccount> _accounts = [];
  List<MailItem> _messages = [];
  List<MailFolder> _folders = const [];
  int _active = 0;
  bool _loading = true;
  bool _syncing = false;
  bool _refreshQueued = false;
  String? _error;
  String _folderPath = 'INBOX';
  bool _searchOpen = false;
  final _search = TextEditingController();
  final Map<String, int> _lastUnreadByEmail = {};
  Timer? _autoSyncTimer;
  tray.TrayIcon? _trayIcon;
  MailItem? _selectedMail;
  final Set<String> _selectedMessageIds = <String>{};
  bool _quitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(_setupWindowsTray());
    }
    _restore();
  }

  @override
  void dispose() {
    _search.dispose();
    _autoSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_accounts.isEmpty) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeForegroundSync());
    } else if (state == AppLifecycleState.paused) {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
      if (Platform.isAndroid) unawaited(_scheduleAndroidBackgroundSync());
    }
  }

  Future<void> _resumeForegroundSync() async {
    _autoSyncTimer?.cancel();
    if (Platform.isAndroid) unawaited(_scheduleAndroidBackgroundSync());
    if (!_quitting && mounted && _accounts.isNotEmpty) {
      _autoSyncTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => unawaited(_autoCheckInboxes()),
      );
    }
  }

  Future<void> _scheduleAndroidBackgroundSync() async {
    if (!Platform.isAndroid || _accounts.isEmpty) return;
    try {
      await AndroidMailBackgroundSync.schedule();
    } catch (_) {
      // Android may defer background jobs when the device restricts battery use.
    }
  }

  Future<void> _setupWindowsTray() async {
    tray.TrayIcon? icon;
    try {
      await windowManager.setTitle('Parmtech Mail');
      icon = tray.TrayIcon.create();
      if (icon == null) return;
      icon.icon = tray.ImageAsset.fromAsset('assets/parmtech-mark.png');
      icon.setTooltip('Parmtech Mail');
      icon.addListener((event) {
        if (event is tray.TrayIconClickedEvent ||
            event is tray.TrayIconDoubleClickedEvent) {
          unawaited(_showFromTray());
        }
      });

      final menu = tray.Menu.create();
      final open = tray.MenuItem.createWithLabelAndType(
        'Open Parmtech Mail',
        tray.MenuItemType.normal,
      );
      final quit = tray.MenuItem.createWithLabelAndType(
        'Quit Parmtech Mail',
        tray.MenuItemType.normal,
      );
      if (menu == null || open == null || quit == null) {
        icon.dispose();
        return;
      }
      open.addListener((event) {
        if (event is tray.MenuItemClickedEvent) unawaited(_showFromTray());
      });
      quit.addListener((event) {
        if (event is tray.MenuItemClickedEvent) unawaited(_quitFromTray());
      });
      menu.addItem(open);
      menu.addSeparator();
      menu.addItem(quit);
      icon.setContextMenu(menu);
      icon.setVisible(true);
      _trayIcon = icon;
      await windowManager.setPreventClose(true);
    } catch (_) {
      _trayIcon = null;
      try {
        icon?.setVisible(false);
        icon?.dispose();
      } catch (_) {}
      try {
        await windowManager.setPreventClose(false);
      } catch (_) {}
    }
  }

  Future<void> _showFromTray() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quitFromTray() async {
    _quitting = true;
    _autoSyncTimer?.cancel();
    final icon = _trayIcon;
    if (icon != null) {
      icon.setVisible(false);
      icon.dispose();
      _trayIcon = null;
    }
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    // Keep mail polling and notifications alive when the user closes the window.
    if (!_quitting && _trayIcon != null) unawaited(windowManager.hide());
  }

  Future<void> _restore() async {
    try {
      await _notifications.initialize();
    } catch (_) {
      /* Notifications may not be available on this host OS. */
    }
    try {
      final saved = await _vault.readAll();
      _lastUnreadByEmail.addAll(await _vault.readUnreadCounts());
      // Render the last encrypted Inbox cache immediately. Network discovery
      // and IMAP sync happen afterwards and must never block the first screen.
      var cachedInbox = <MailItem>[];
      if (saved.isNotEmpty) {
        try {
          final raw = await _vault.readMailCache(saved.first.id, 'INBOX');
          if (raw != null) {
            cachedInbox = (jsonDecode(raw) as List<dynamic>)
                .map((entry) => MailItem.fromJson(entry as Map<String, dynamic>))
                .toList(growable: true);
          }
        } catch (_) {
          // Ignore corrupt local cache, then fetch fresh messages.
        }
      }
      if (!mounted) return;
      setState(() {
        _accounts = saved;
        _messages = cachedInbox;
        _selectedMail = cachedInbox.isEmpty ? null : cachedInbox.first;
        _loading = false;
      });
      if (saved.isNotEmpty) {
        unawaited(_activateAutomaticBackgroundMail());
        unawaited(_loadFolders());
        unawaited(_refresh());
        unawaited(_seedUnreadCounts());
      } else if (Platform.isAndroid) {
        try {
          await AndroidMailBackgroundSync.cancel();
          await LiveMailService.stop();
        } catch (_) {}
      }
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        await _scheduleAndroidBackgroundSync();
      } else {
        await _resumeForegroundSync();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Secure account storage is unavailable. ${friendlyMailError(e)}';
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _accounts.isEmpty) return;
    if (_syncing) {
      _refreshQueued = true;
      return;
    }
    final account = _accounts[_active];
    final folderPath = _folderPath;
    setState(() {
      _syncing = true;
      _error = null;
    });
    if (_messages.isEmpty) {
      try {
        final cached = await _vault.readMailCache(account.id, folderPath);
        if (cached != null && mounted && _accounts.isNotEmpty &&
            _accounts[_active].id == account.id && _folderPath == folderPath) {
          final records = jsonDecode(cached) as List<dynamic>;
          setState(() => _messages = records
              .map((entry) => MailItem.fromJson(entry as Map<String, dynamic>))
              .toList(growable: true));
        }
      } catch (_) {
        // A damaged cache never prevents a fresh server sync.
      }
    }
    try {
      final items = await _service.fetchFolder(account, folderPath);
      // Account removal may happen while IMAP is fetching. Do not recreate a
      // removed account's private cached messages after logout.
      if (!mounted || !_accounts.any((saved) => saved.id == account.id)) return;
      await _vault.writeMailCache(account.id, folderPath,
          jsonEncode(items.map((message) => message.toJson()).toList()));
      if (!_accounts.any((saved) => saved.id == account.id)) {
        await _vault.remove(account.email);
        return;
      }
      final isInbox = folderPath.toUpperCase() == 'INBOX';
      final currentUnread = isInbox
          ? await _service.countUnread(account)
          : items.where((m) => m.unread).length;
      final previousUnread = _lastUnreadByEmail[account.id];
      if (isInbox &&
          previousUnread != null &&
          currentUnread > previousUnread &&
          _accounts.any((saved) => saved.id == account.id)) {
        try {
          await _notifications.showNewMail(currentUnread - previousUnread);
        } catch (_) {
          /* Notification permission is optional. */
        }
      }
      if (isInbox && _accounts.any((saved) => saved.id == account.id)) {
        _lastUnreadByEmail[account.id] = currentUnread;
      }
      if (mounted &&
          _accounts.isNotEmpty &&
          _accounts[_active].id == account.id &&
          _folderPath == folderPath) {
        setState(() {
          _messages = items;
          _selectedMail = items.where((m) => m.identity == _selectedMail?.identity).firstOrNull ??
                    (items.isEmpty ? null : items.first);
        });
      }
      await _vault.writeUnreadCounts(_lastUnreadByEmail);
    } catch (e) {
      if (mounted &&
          _accounts.isNotEmpty &&
          _accounts[_active].id == account.id) {
        setState(() => _error = friendlyMailError(e));
      }
    } finally {
      if (mounted) {
        final shouldRefresh = _refreshQueued;
        _refreshQueued = false;
        setState(() => _syncing = false);
        if (shouldRefresh) unawaited(_refresh());
      }
    }
  }

  /// Always schedule available Android checks for signed-in mail accounts.
  /// On newer Android devices a foreground service is best-effort and may be
  /// stopped by device battery restrictions. WorkManager remains the fallback.
  Future<void> _activateAutomaticBackgroundMail() async {
    if (!Platform.isAndroid || _accounts.isEmpty) return;
    await _scheduleAndroidBackgroundSync();
    try {
      await LiveMailService.start();
    } catch (_) {
      // WorkManager fallback is still active when Android blocks the service.
    }
  }

  Future<void> _autoCheckInboxes() async {
    if (!mounted || _accounts.isEmpty || _syncing) return;
    final accounts = List<MailAccount>.of(_accounts);
    final activeAccountId = _accounts[_active].id;
    var newMailCount = 0;
    setState(() => _syncing = true);
    try {
      // Bound concurrency to two accounts: much faster across several
      // mailboxes without overwhelming a cPanel shared-hosting server.
      for (var start = 0; start < accounts.length; start += 2) {
        await Future.wait(accounts.skip(start).take(2).map((account) async {
          try {
            final unread = await _service.countUnread(account);
            if (!mounted || !_accounts.any((saved) => saved.id == account.id)) {
              return;
            }
            final previous = _lastUnreadByEmail[account.id];
            _lastUnreadByEmail[account.id] = unread;
            if (previous != null && unread > previous) {
              newMailCount += unread - previous;
            }
            final isActiveInbox = account.id == activeAccountId &&
                _accounts.isNotEmpty &&
                _accounts[_active].id == account.id &&
                _folderPath.toUpperCase() == 'INBOX';
            if (isActiveInbox) {
              final items = await _service.fetchInbox(account);
              if (!mounted ||
                  !_accounts.any((saved) => saved.id == account.id)) {
                return;
              }
              await _vault.writeMailCache(account.id, 'INBOX',
                  jsonEncode(items.map((item) => item.toJson()).toList()));
              if (!mounted ||
                  _accounts.isEmpty ||
                  _accounts[_active].id != account.id ||
                  _folderPath.toUpperCase() != 'INBOX') {
                return;
              }
              setState(() {
                _messages = items;
                _selectedMail = items
                        .where((item) => item.identity == _selectedMail?.identity)
                        .firstOrNull ??
                    (items.isEmpty ? null : items.first);
              });
            }
          } catch (_) {
            // Retain the previous unread snapshot until a successful poll.
          }
        }));
      }
      if (newMailCount > 0) {
        try {
          await _notifications.showNewMail(newMailCount);
        } catch (_) {}
      }
      final activeIds = _accounts.map((account) => account.id).toSet();
      _lastUnreadByEmail.removeWhere((id, _) => !activeIds.contains(id));
      await _vault.writeUnreadCounts(_lastUnreadByEmail);
    } finally {
      if (mounted) {
        final shouldRefresh = _refreshQueued;
        _refreshQueued = false;
        setState(() => _syncing = false);
        if (shouldRefresh) unawaited(_refresh());
      }
    }
  }

  Future<void> _seedUnreadCounts() async {
    if (_accounts.isEmpty) return;
    try {
      final counts = await _vault.readUnreadCounts();
      counts.addAll(_lastUnreadByEmail);
      for (final account in List<MailAccount>.of(_accounts)) {
        if (counts.containsKey(account.id)) continue;
        try {
          counts[account.id] = await _service.countUnread(account);
        } catch (_) {
          // The next successful sync will establish this account's baseline.
        }
      }
      final currentIds = _accounts.map((account) => account.id).toSet();
      counts.removeWhere((id, _) => !currentIds.contains(id));
      _lastUnreadByEmail.removeWhere((id, _) => !currentIds.contains(id));
      _lastUnreadByEmail.addAll(counts);
      await _vault.writeUnreadCounts(_lastUnreadByEmail);
    } catch (_) {}
  }

  Future<void> _loadFolders() async {
    if (_accounts.isEmpty) return;
    final account = _accounts[_active];
    try {
      final folders = await _service.listFolders(account);
      if (mounted &&
          _accounts.isNotEmpty &&
          _accounts[_active].id == account.id) {
        setState(() {
          _folders = folders;
          if (_folderPath != 'INBOX' &&
              !folders.any((f) => f.path == _folderPath)) {
            _folderPath = 'INBOX';
          }
        });
      }
    } catch (_) {
      /* Keep the Inbox shortcut available if LIST is unsupported. */
    }
  }

  Future<void> _selectFolder(MailFolder folder) async {
    setState(() {
      _folderPath = folder.path;
      _messages = [];
      _selectedMail = null;
      _selectedMessageIds.clear();
    });
    await _refresh();
  }

  Future<void> _addAccount() async {
    if (_syncing) {
      _notice('Please wait for the current mail check to finish.');
      return;
    }
    if (_accounts.length >= SecureAccountVault.maxAccounts) {
      _notice('You can add up to 10 accounts.');
      return;
    }
    final account = await Navigator.of(context).push<MailAccount>(
      MaterialPageRoute(builder: (_) => const AddAccountPage()),
    );
    if (account == null || !mounted) return;
    var refreshAfterConnect = false;
    setState(() => _syncing = true);
    try {
      final verified = account; // Verified in AddAccountPage before closing.
      await _vault.add(verified);
      if (!mounted) return;
      setState(() {
        _accounts = [..._accounts.where((a) => a.id != verified.id), verified];
        _active = _accounts.indexWhere((a) => a.id == verified.id);
        _messages = [];
        _selectedMail = null;
      });
      if (_accounts.length == 1) {
        try {
          await _notifications.requestPermission();
        } catch (_) {}
      }
      unawaited(_seedUnreadCounts());
      unawaited(_activateAutomaticBackgroundMail());
      refreshAfterConnect = true;
      await _loadFolders();
    } catch (e) {
      if (mounted) _notice(friendlyMailError(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (refreshAfterConnect && mounted) {
      _refreshQueued = false;
      await _refresh();
    }
  }

  Future<void> _compose() async {
    if (_accounts.isEmpty) {
      await _addAccount();
      return;
    }
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ComposePage(account: _accounts[_active], service: _service),
      ),
    );
    if (sent == true) await _refresh();
  }

  Future<void> _open(MailItem message, {List<MailItem> conversation = const []}) async {
    if (message.unread) unawaited(_actOnMail(message, 'read'));
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MailDetailPage(
          message: message,
          conversation: conversation,
          account: _accounts.isEmpty ? null : _accounts[_active],
          service: _service,
          folders: _folders,
          onAction: (action) => _actOnMail(message, action),
          onMove: (folder) async {
            await _service.moveMessage(_accounts[_active], message, folder.path);
            if (mounted) setState(() => _messages.removeWhere((m) => m.identity == message.identity));
          },
          onSent: _refresh,
        ),
      ),
    );
  }

  Future<void> _saveCurrentFolderSnapshot(MailAccount account, String folderPath) async {
    if (!mounted || _accounts.isEmpty ||
        _accounts[_active].id != account.id || _folderPath != folderPath) return;
    final snapshot = List<MailItem>.of(_messages);
    await _vault.writeMailCache(account.id, folderPath,
        jsonEncode(snapshot.map((mail) => mail.toJson()).toList()));
  }

  Future<void> _actOnMail(MailItem message, String action) async {
    if (_accounts.isEmpty) return;
    final account = _accounts[_active];
    try {
      switch (action) {
        case 'delete':
          await _service.deleteMessage(account, message);
          break;
        case 'read':
          await _service.setRead(account, message, true);
          break;
        case 'unread':
          await _service.setRead(account, message, false);
          break;
        case 'star':
          await _service.setStarred(account, message, !message.starred);
          break;
        case 'spam':
          final spam = _folders.where((f) => _folderTitle(f).toLowerCase() == 'spam');
          if (spam.isEmpty) throw const MailConnectionException('No Spam folder is available on this server.');
          await _service.moveMessage(account, message, spam.first.path);
          break;
        case 'archive':
          final archive = _folders.where((f) => _folderTitle(f).toLowerCase() == 'archive');
          if (archive.isEmpty) throw const MailConnectionException('No Archive folder is available on this server.');
          await _service.moveMessage(account, message, archive.first.path);
          break;
      }
      if (mounted) {
        setState(() {
          if (action == 'delete' || action == 'spam' || action == 'archive') {
            _messages.removeWhere((m) => m.identity == message.identity);
            _selectedMessageIds.remove(message.identity);
          } else {
            final index = _messages.indexWhere((m) => m.identity == message.identity);
            if (index >= 0) {
              _messages[index] = _messages[index].copyWith(
                unread: action == 'read' ? false : action == 'unread' ? true : null,
                starred: action == 'star' ? !message.starred : null,
              );
            }
          }
        });
        if (action == 'delete' || action == 'spam' || action == 'archive') {
          _selectedMail = _messages.where(
              (mail) => mail.identity == _selectedMail?.identity
          ).firstOrNull ?? _messages.firstOrNull;
        }
        await _saveCurrentFolderSnapshot(account, message.mailboxPath);
        _notice(action == 'read' ? 'Marked as read.' : action == 'unread' ? 'Marked as unread.' : action == 'star' ? 'Star updated.' : 'Message moved.');
      }
    } catch (e) {
      if (mounted && (action == 'delete' || action == 'archive' || action == 'spam')) await _refresh();
      if (mounted) _notice(friendlyMailError(e));
    }
  }

  Future<void> _showMailActions(MailItem message) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(22, 4, 22, 10), child: Align(alignment: Alignment.centerLeft, child: Text(message.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _sheetAction(ctx, Icons.delete_outline, 'Delete', 'delete'),
          _sheetAction(ctx, Icons.check_box_outlined, 'Select', 'select'),
        ]),
        ListTile(leading: const Icon(Icons.mark_email_read_outlined), title: Text(message.unread ? 'Mark as read' : 'Mark as unread'), onTap: () => Navigator.pop(ctx, message.unread ? 'read' : 'unread')),
        ListTile(leading: const Icon(Icons.star_outline), title: Text(message.starred ? 'Remove star' : 'Add star'), onTap: () => Navigator.pop(ctx, 'star')),
        ListTile(leading: const Icon(Icons.archive_outlined), title: const Text('Archive'), onTap: () => Navigator.pop(ctx, 'archive')),
        if (_folders.any((folder) => folder.path != message.mailboxPath && !_isSystemFolder(folder)))
          ListTile(leading: const Icon(Icons.drive_file_move_outline), title: const Text('Move to folder'), onTap: () => Navigator.pop(ctx, 'move')),
        ListTile(leading: const Icon(Icons.report_gmailerrorred_outlined), title: const Text('Mark as spam'), onTap: () => Navigator.pop(ctx, 'spam')),
        ListTile(leading: const Icon(Icons.person_remove_outlined), title: Text('Delete loaded messages from ${message.sender}'), onTap: () => Navigator.pop(ctx, 'sender')),
      ])),
    );
    if (action == 'select') {
      setState(() => _selectedMessageIds.add(message.identity));
    } else if (action == 'sender') {
      final sameSender = message.senderAddress.trim().isEmpty
          ? <MailItem>[message]
          : _messages.where((m) => m.senderAddress.toLowerCase() == message.senderAddress.toLowerCase()).toList();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete sender messages?'),
          content: Text('This deletes ${sameSender.length} currently loaded message(s) from ${message.sender}. Other server messages are not included.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (confirmed != true || !mounted || _accounts.isEmpty) return;
      try {
        await _service.deleteMessages(_accounts[_active], sameSender);
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => sameSender.any((item) => item.identity == m.identity));
            _selectedMessageIds.removeAll(sameSender.map((m) => m.identity));
            _selectedMail = _messages.firstOrNull;
          });
          await _saveCurrentFolderSnapshot(_accounts[_active], _folderPath);
        }
      } catch (e) { if (mounted) _notice(friendlyMailError(e)); }
    } else if (action == 'move') {
      if (!mounted) return;
      final targets = _folders.where((folder) => folder.path != message.mailboxPath).toList();
      final target = await showModalBottomSheet<MailFolder>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [for (final folder in targets) ListTile(leading: Icon(_folderIcon(folder)), title: Text(_folderTitle(folder)), onTap: () => Navigator.pop(ctx, folder))])));
      if (target != null) {
        try { await _service.moveMessage(_accounts[_active], message, target.path); if (mounted) setState(() => _messages.removeWhere((m) => m.identity == message.identity)); }
        catch (e) { if (mounted) _notice(friendlyMailError(e)); }
      }
    } else if (action != null) {
      await _actOnMail(message, action);
    }
  }

  bool _isSystemFolder(MailFolder folder) => const {'inbox', 'sent', 'drafts', 'trash', 'spam', 'archive'}.contains(_folderTitle(folder).toLowerCase());

  Widget _sheetAction(BuildContext context, IconData icon, String label, String result) => SizedBox(width: 150, child: FilledButton.tonalIcon(onPressed: () => Navigator.pop(context, result), icon: Icon(icon), label: Text(label)));

  Future<void> _createFolder() async {
    if (_accounts.isEmpty) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Create folder'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Create'))],
    ));
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try { await _service.createFolder(_accounts[_active], name); await _loadFolders(); }
    catch (e) { if (mounted) _notice(friendlyMailError(e)); }
  }

  Future<void> _bulkDelete() async {
    final selected = _messages.where((m) => _selectedMessageIds.contains(m.identity)).toList();
    if (selected.isEmpty || _accounts.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected messages?'),
        content: Text('Move ${selected.length} message(s) to Trash, or permanently delete them if this server has no Trash folder?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted || _accounts.isEmpty) return;
    try {
      await _service.deleteMessages(_accounts[_active], selected);
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => _selectedMessageIds.contains(m.identity));
          _selectedMessageIds.clear();
          _selectedMail = _messages.firstOrNull;
        });
        await _saveCurrentFolderSnapshot(_accounts[_active], _folderPath);
      }
    } catch (e) { if (mounted) _notice(friendlyMailError(e)); }
  }

  Future<String?> _askBackupPassphrase({required bool confirm}) async {
    final controller = TextEditingController();
    final repeat = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(confirm ? 'Protect backup' : 'Unlock backup'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('This passphrase encrypts mailbox passwords and saved mail. You will need it to restore the file.'),
        const SizedBox(height: 14),
        TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Backup passphrase')),
        if (confirm) ...[const SizedBox(height: 10), TextField(controller: repeat, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm passphrase'))],
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () {
        if (controller.text.length < 10 || (confirm && repeat.text != controller.text)) return;
        Navigator.pop(ctx, controller.text);
      }, child: Text(confirm ? 'Encrypt' : 'Unlock'))],
    ));
    controller.dispose();
    repeat.dispose();
    return result;
  }

  Future<void> _exportBackup() async {
    if (_accounts.isEmpty) { _notice('Connect an account before creating a backup.'); return; }
    final passphrase = await _askBackupPassphrase(confirm: true);
    if (passphrase == null) return;
    try {
      final caches = <String, Object?>{};
      for (final account in _accounts) {
        final stored = await _vault.readMailCaches(account.id);
        caches[account.id] = {
          for (final entry in stored.entries) entry.key: jsonDecode(entry.value),
        };
      }
      final bytes = await EncryptedMailBackup.encrypt({
        'accounts': _accounts.map((account) => account.toJson()).toList(),
        'mailCache': caches,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }, passphrase);
      final path = await FilePicker.saveFile(
        fileName: 'Parmtech-Mail-Backup.ptmail',
        bytes: bytes,
      );
      if (path != null && mounted) _notice('Encrypted backup saved. Keep the passphrase safe.');
    } catch (e) { if (mounted) _notice('Backup could not be created: ${friendlyMailError(e)}'); }
  }

  Future<void> _importBackup() async {
    final selectedFile = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['ptmail']);
    if (selectedFile == null) return;
    final passphrase = await _askBackupPassphrase(confirm: false);
    if (passphrase == null) return;
    try {
      final payload = await EncryptedMailBackup.decrypt(await selectedFile.readAsBytes(), passphrase);
      final incoming = (payload['accounts'] as List<dynamic>)
          .map((entry) => MailAccount.fromJson(entry as Map<String, dynamic>)).toList();
      final byId = <String, MailAccount>{for (final item in _accounts) item.id: item, for (final item in incoming) item.id: item};
      if (byId.length > SecureAccountVault.maxAccounts) throw const AccountLimitReachedException();
      await _vault.replaceAll(byId.values.toList());
      final caches = payload['mailCache'];
      if (caches is Map<String, dynamic>) {
        for (final entry in caches.entries) {
          // Never import unrelated caches from a malformed backup.
          if (!byId.containsKey(entry.key)) continue;
          final folders = entry.value;
          if (folders is! Map<String, dynamic>) continue;
          for (final folder in folders.entries) {
            if (folder.key.isEmpty || folder.key.length > 512 || folder.value is! List) {
              continue;
            }
            await _vault.writeMailCache(entry.key, folder.key, jsonEncode(folder.value));
          }
        }
      }
      if (!mounted) return;
      setState(() { _accounts = byId.values.toList(); _active = 0; _folderPath = 'INBOX'; _messages = []; _folders = const []; });
      unawaited(_activateAutomaticBackgroundMail());
      await _loadFolders();
      await _refresh();
      if (mounted) _notice('Backup restored on this device.');
    } catch (e) { if (mounted) _notice('Could not restore backup. Check the file and passphrase. ${friendlyMailError(e)}'); }
  }

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) {
    final account = _accounts.isEmpty ? null : _accounts[_active];
    return Scaffold(
      drawer: _drawer(),
      appBar: AppBar(
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PARMTECH MAIL',
              style: TextStyle(
                color: _orange,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1.8,
              ),
            ),
            Text(
              account?.email ?? 'Your inbox',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -.3),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _syncing ? null : _refresh,
            tooltip: 'Sync',
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
          if (account != null && _selectedMessageIds.isNotEmpty) ...[
            IconButton(onPressed: _bulkDelete, tooltip: 'Delete selected', icon: const Icon(Icons.delete_outline_rounded)),
            IconButton(onPressed: () => setState(() => _selectedMessageIds.clear()), tooltip: 'Clear selection', icon: const Icon(Icons.close_rounded)),
          ],
          if (account != null) IconButton(
            onPressed: () => setState(() => _searchOpen = !_searchOpen),
            tooltip: 'Search',
            icon: Icon(
              _searchOpen ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
          IconButton(
            onPressed: _accountPicker,
            tooltip: 'Accounts',
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 1120 && _accounts.isNotEmpty) {
                  return _desktopLayout(account);
                }
                return Column(
                  children: [
                    _header(account),
                    if (_error != null) _errorCard(),
                    if (_searchOpen && _accounts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Search sender, subject or message',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _accounts.isEmpty
                          ? _welcome()
                          : _messages.isEmpty && !_syncing
                          ? _emptyInbox()
                          : _messageList(),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: account == null ? null : FloatingActionButton.small(
        tooltip: 'Compose email',
        onPressed: _compose,
        backgroundColor: _orange,
        foregroundColor: Colors.white,
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }

  Widget _desktopLayout(MailAccount? account) {
    final colors = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _messages
        : _messages.where((mail) =>
            '${mail.sender} ${mail.subject} ${mail.body}'
                .toLowerCase().contains(query)).toList();
    final conversations = groupMailConversations(visible);
    final preferred = _selectedMail?.identity;
    final selected = conversations
            .where((item) => item.latest.identity == preferred)
            .map((item) => item.latest)
            .firstOrNull ??
        conversations.firstOrNull?.latest;

    return LayoutBuilder(
      builder: (context, limits) {
        final narrow = limits.maxWidth < 1360;
        final sidebarWidth = narrow ? 212.0 : 240.0;
        final listWidth = narrow ? 330.0 : 390.0;
        return Row(
          children: [
            SizedBox(
              width: sidebarWidth,
              child: ColoredBox(
                color: colors.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(17, 19, 15, 20),
                      child: Row(children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(Icons.mark_email_unread_rounded,
                              color: colors.onPrimary, size: 21),
                        ),
                        const SizedBox(width: 11),
                        const Expanded(
                          child: Text('ParmTech Mail',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.5)),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FilledButton.icon(
                        onPressed: _compose,
                        icon: const Icon(Icons.edit_rounded, size: 17),
                        label: const Text('New message'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Expanded(
                      // A scrollable sidebar is required for 10 accounts and
                      // many custom folders; the old Column could overflow.
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: [
                          const _DesktopSectionLabel('YOUR MAIL'),
                          _desktopNavTile(Icons.inbox_rounded, 'Inbox',
                            _folderPath.toUpperCase() == 'INBOX',
                            () {
                              setState(() {
                                _folderPath = 'INBOX';
                                _messages = [];
                                _selectedMail = null;
                                _selectedMessageIds.clear();
                              });
                              unawaited(_refresh());
                            }),
                          for (final folder in _folders.where(
                              (entry) => entry.path.toUpperCase() != 'INBOX'))
                            _desktopNavTile(
                              _folderIcon(folder), _folderTitle(folder),
                              folder.path == _folderPath,
                              () => _selectFolder(folder),
                              trailing: folder.unread > 0
                                  ? '${folder.unread}' : null),
                          const SizedBox(height: 15),
                          const _DesktopSectionLabel('ACCOUNTS'),
                          for (final mailbox in _accounts)
                            ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor:
                                    colors.primary.withValues(alpha: .12),
                                child: Text(mailbox.email[0].toUpperCase(),
                                  style: TextStyle(color: colors.primary,
                                    fontSize: 11, fontWeight: FontWeight.w800)),
                              ),
                              title: Text(mailbox.email,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                              selected: mailbox.id == account?.id,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                              onTap: () {
                                setState(() {
                                  _active = _accounts.indexOf(mailbox);
                                  _folderPath = 'INBOX';
                                  _messages = [];
                                  _selectedMail = null;
                                  _folders = const [];
                                  _selectedMessageIds.clear();
                                });
                                unawaited(_loadFolders()
                                    .then((_) => _refresh()));
                              },
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: colors.outlineVariant),
                    _desktopNavTile(Icons.settings_rounded, 'Settings',
                        false, () => unawaited(_openSettings())),
                    _desktopNavTile(Icons.person_add_alt_1_rounded,
                        'Add account', false, () => unawaited(_addAccount())),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 5, 12, 13),
                      child: Row(children: [
                        Icon(Icons.lock_outline_rounded, size: 12,
                            color: colors.primary),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Secure private mail',
                          style: TextStyle(fontSize: 10, color: _muted))),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1,
                color: colors.outlineVariant),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(narrow ? 16 : 22, 15,
                        narrow ? 16 : 22, 14),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_activeFolderName,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 25,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.8)),
                            const SizedBox(height: 3),
                            Text(account?.email ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12,
                                color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: narrow ? 210 : 295,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Search mail or people',
                            prefixIcon: Icon(Icons.search_rounded),
                            isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _syncing ? null : _refresh,
                        tooltip: 'Check mail now',
                        icon: _syncing
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2))
                            : const Icon(Icons.sync_rounded),
                      ),
                    ]),
                  ),
                  if (_error != null) _errorCard(),
                  Expanded(
                    child: Row(children: [
                      SizedBox(
                        width: listWidth,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 5, 14, 9),
                              child: Row(children: [
                                Text('CONVERSATIONS',
                                  style: TextStyle(fontSize: 10,
                                    letterSpacing: 1.25,
                                    color: colors.primary,
                                    fontWeight: FontWeight.w900)),
                                const Spacer(),
                                Text('${conversations.length}',
                                  style: TextStyle(fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            Expanded(
                              child: _syncing && _messages.isEmpty
                                  ? const Center(child:
                                      CircularProgressIndicator())
                                  : conversations.isEmpty
                                    ? _emptyInbox()
                                    : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                          9, 3, 9, 14),
                                      itemCount: conversations.length,
                                      separatorBuilder: (_, _) => SizedBox(
                                        height: widget.appearance.layout ==
                                            MailLayout.compact ? 3 : 8),
                                      itemBuilder: (context, index) {
                                        final item = conversations[index];
                                        return _tile(item.latest,
                                          selected: item.latest.identity ==
                                              selected?.identity,
                                          threadCount: item.count,
                                          onTap: () => setState(
                                            () => _selectedMail = item.latest));
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      VerticalDivider(width: 1, thickness: 1,
                          color: colors.outlineVariant),
                      Expanded(child: _desktopMessagePreview(selected)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 7, 18, 9),
                    child: Text(
                      _syncing
                          ? 'Checking for new mail…'
                          : '${_messages.length} messages · Background checks enabled',
                      style: TextStyle(fontSize: 10.5,
                          color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _desktopNavTile(
    IconData icon, String label, bool selected,
    VoidCallback onTap, {String? trailing}
  ) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(icon, size: 18,
          color: selected ? colors.primary : colors.onSurfaceVariant),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
      trailing: trailing == null ? null :
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .11),
            borderRadius: BorderRadius.circular(8)),
          child: Text(trailing, style: TextStyle(fontSize: 10,
            fontWeight: FontWeight.w800, color: colors.primary))),
      selected: selected,
      selectedTileColor: colors.primary.withValues(alpha: .09),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10)),
      onTap: onTap,
    );
  }

  Future<void> _desktopWrite(MailItem mail, {bool forward = false}) async {
    if (_accounts.isEmpty) return;
    final originalSubject = mail.subject.isEmpty ? '(No subject)' : mail.subject;
    final subject = forward
        ? 'Fwd: $originalSubject'
        : originalSubject.toLowerCase().startsWith('re:')
            ? originalSubject
            : 'Re: $originalSubject';
    final body = forward
        ? '\n\n---------- Forwarded message ----------\n'
            'From: ${mail.senderAddress}\nDate: ${mail.time}\n'
            'Subject: $originalSubject\n\n${mail.body}'
        : '\n\nOn ${mail.time}, ${mail.sender} wrote:\n'
            '> ${mail.body.replaceAll('\n', '\n> ')}';
    final recipient = forward ? '' : mail.replyToAddress.isNotEmpty
        ? mail.replyToAddress : mail.senderAddress;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ComposePage(
        account: _accounts[_active],
        service: _service,
        initialTo: recipient,
        initialSubject: subject,
        initialBody: body,
        inReplyTo: forward ? null : mail.messageId,
        references: forward ? null : mail.references,
      )),
    );
    if (sent == true && mounted) await _refresh();
  }

  Widget _desktopMessagePreview(MailItem? mail) {
    final colors = Theme.of(context).colorScheme;
    if (mail == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.mark_email_read_outlined, size: 49,
            color: colors.primary.withValues(alpha: .7)),
        const SizedBox(height: 13),
        const Text('Select a conversation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Messages appear here, without opening a new window.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12,
              color: colors.onSurfaceVariant)),
      ]));
    }
    final initial = mail.sender.trim().isEmpty
        ? '?' : mail.sender.trim()[0].toUpperCase();
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(17, 6, 14, 6),
        decoration: BoxDecoration(border: Border(
            bottom: BorderSide(color: colors.outlineVariant))),
        child: Row(children: [
          const Expanded(child: Text('MESSAGE',
            style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w900, letterSpacing: 1.2))),
          IconButton(
            onPressed: () => unawaited(_actOnMail(mail, 'archive')),
            tooltip: 'Archive', icon: const Icon(Icons.archive_outlined,
                size: 19)),
          IconButton(
            onPressed: () => unawaited(_actOnMail(mail, 'star')),
            tooltip: 'Star or unstar',
            icon: Icon(mail.starred ? Icons.star_rounded :
                Icons.star_border_rounded, size: 19)),
          IconButton(
            onPressed: () => unawaited(_actOnMail(mail, 'delete')),
            tooltip: 'Move to trash',
            icon: const Icon(Icons.delete_outline_rounded, size: 19)),
          IconButton(
            onPressed: () => unawaited(_open(mail)),
            tooltip: 'Open full message',
            icon: const Icon(Icons.open_in_new_rounded, size: 18)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 21, 24, 20),
          children: [
            Text(mail.subject.isEmpty ? '(No subject)' : mail.subject,
              style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 24,
                letterSpacing: -.7, height: 1.22)),
            const SizedBox(height: 20),
            Row(children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: colors.primary.withValues(alpha: .13),
                child: Text(initial, style: TextStyle(
                  color: colors.primary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mail.sender,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(mail.senderAddress,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11,
                      color: colors.onSurfaceVariant)),
                ],
              )),
              const SizedBox(width: 8),
              Text(mail.time,
                style: TextStyle(fontSize: 10.5,
                    color: colors.onSurfaceVariant)),
            ]),
            const SizedBox(height: 20),
            Material(
              color: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .55))),
              child: Padding(
                padding: const EdgeInsets.all(19),
                child: SelectableText(
                  mail.body.isEmpty
                      ? 'This message has no readable plain-text content.'
                      : mail.body,
                  style: const TextStyle(
                    fontSize: 13.5, height: 1.65),
                ),
              ),
            ),
          ],
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(17, 10, 17, 15),
        decoration: BoxDecoration(border: Border(
            top: BorderSide(color: colors.outlineVariant))),
        child: Row(children: [
          FilledButton.icon(
            onPressed: () => unawaited(_desktopWrite(mail)),
            icon: const Icon(Icons.reply_rounded, size: 16),
            label: const Text('Reply')),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => unawaited(_desktopWrite(mail, forward: true)),
            icon: const Icon(Icons.forward_rounded, size: 16),
            label: const Text('Forward')),
          const Spacer(),
          IconButton(
            tooltip: 'More options, print and attachments',
            onPressed: () => unawaited(_open(mail)),
            icon: const Icon(Icons.more_horiz_rounded)),
        ]),
      ),
    ]);
  }

  Widget _header(MailAccount? account) {
    final colors = Theme.of(context).colorScheme;
    final conversations = groupMailConversations(_messages).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 11),
      padding: const EdgeInsets.fromLTRB(17, 17, 17, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _panel,
            _orange.withValues(alpha: _darkTheme ? .17 : .075),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _orange.withValues(alpha: .13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeFolderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                        letterSpacing: -1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _sky,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _syncing
                              ? 'SYNCING YOUR MAIL'
                              : '$conversations CONVERSATIONS',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (account != null) _connectionPill(),
            ],
          ),
          if (_folders.isNotEmpty) ...[
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _folders.map((folder) {
                  final selected = folder.path == _folderPath;
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      showCheckmark: false,
                      avatar: selected
                          ? const Icon(Icons.check_rounded, size: 15)
                          : null,
                      label: Text(_folderTitle(folder)),
                      selected: selected,
                      onSelected: (_) => _selectFolder(folder),
                      selectedColor: _orange.withValues(alpha: .18),
                      backgroundColor: colors.surface.withValues(alpha: .8),
                      labelStyle: TextStyle(
                        color: selected ? colors.primary : colors.onSurface,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: selected
                            ? _orange.withValues(alpha: .36)
                            : colors.outlineVariant.withValues(alpha: .48),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _connectionPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _orange.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _orange.withValues(alpha: .16)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_rounded, size: 14, color: _orange),
            SizedBox(width: 5),
            Text('SECURE',
                style: TextStyle(
                  color: _orange,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                )),
          ],
        ),
      );

  Widget _messageList() {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _messages
        : _messages
              .where(
                (m) => '${m.sender} ${m.subject} ${m.body}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList();
    if (visible.isEmpty && query.isNotEmpty) {
      return Center(
        child: Text(
          'No messages match “${_search.text.trim()}”.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      );
    }
    final conversations = groupMailConversations(visible);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(widget.appearance.layout == MailLayout.compact ? 9 : 14, 2, widget.appearance.layout == MailLayout.compact ? 9 : 14, 100),
            itemCount: conversations.length,
            separatorBuilder: (_, _) => SizedBox(height: widget.appearance.layout == MailLayout.compact ? 2 : widget.appearance.layout == MailLayout.cards ? 13 : 7),
            itemBuilder: (context, index) => _tile(
              conversations[index].latest,
              compact: true,
              threadCount: conversations[index].count,
              onTap: () => _open(
                conversations[index].latest,
                conversation: conversations[index].messages,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(
    MailItem mail, {
    bool selected = false,
    bool compact = false,
    int threadCount = 1,
    VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    final compactStyle = widget.appearance.layout == MailLayout.compact;
    final cardsStyle = widget.appearance.layout == MailLayout.cards;
    final selectedForAction = _selectedMessageIds.contains(mail.identity);
    final highlighted = selected || selectedForAction;
    const avatarPalette = <Color>[
      Color(0xFF5365D9),
      Color(0xFF07889D),
      Color(0xFF9562C2),
      Color(0xFFC46D52),
    ];
    final senderHash = mail.sender.codeUnits.fold<int>(0, (a, b) => a + b);
    final avatarColor = avatarPalette[senderHash % avatarPalette.length];
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardsStyle ? 23 : compactStyle ? 10 : 17),
      side: BorderSide(
        color: highlighted
            ? _orange.withValues(alpha: .38)
            : colors.outlineVariant.withValues(alpha: _darkTheme ? .3 : .5),
      ),
    );
    final tile = Material(
      color: highlighted
          ? _orange.withValues(alpha: _darkTheme ? .21 : .095)
          : mail.unread
              ? (_darkTheme
                  ? const Color(0xFF202D45)
                  : Colors.white)
              : _panel,
      shape: shape,
      elevation: 0,
      child: InkWell(
        customBorder: shape,
        onTap: () {
          if (_selectedMessageIds.isNotEmpty) {
            setState(() {
              if (!_selectedMessageIds.add(mail.identity)) {
                _selectedMessageIds.remove(mail.identity);
              }
            });
          } else if (onTap != null) {
            onTap();
          } else {
            _open(mail);
          }
        },
        onLongPress: () => setState(() { _selectedMessageIds.add(mail.identity); }),
        onSecondaryTap: () => _showMailActions(mail),
        child: Semantics(
          button: true,
          label: 'Email from ${mail.sender}. ${mail.subject}. ${mail.time}',
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compactStyle ? 10 : cardsStyle ? 19 : compact ? 13 : 15,
              vertical: compactStyle ? 8 : cardsStyle ? 20 : compact ? 13 : 15,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: compactStyle ? 34 : cardsStyle ? 52 : compact ? 43 : 46,
                  height: compactStyle ? 34 : cardsStyle ? 52 : compact ? 43 : 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: avatarColor.withValues(alpha: _darkTheme ? .23 : .13),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    mail.sender.trim().isEmpty
                        ? '?'
                        : mail.sender.trim()[0].toUpperCase(),
                    style: TextStyle(
                      color: _darkTheme
                          ? Color.lerp(avatarColor, Colors.white, .32)
                          : avatarColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: -.5,
                    ),
                  ),
                ),
                SizedBox(width: compactStyle ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              mail.sender,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: mail.unread
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                                fontSize: compactStyle ? 13 : cardsStyle ? 16 : compact ? 14 : 15,
                                height: 1.15,
                                letterSpacing: -.25,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            mail.sentAt == null
                                ? mail.time
                                : formatInboxTimestamp(mail.sentAt!),
                            maxLines: 1,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: mail.unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          if (mail.unread) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.circle, size: 7, color: _orange),
                          ],
                        ],
                      ),
                      SizedBox(height: compactStyle ? 2 : 6),
                      Text(
                        mail.subject.isEmpty ? '(No subject)' : mail.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: mail.unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                          fontSize: compactStyle ? 12.5 : cardsStyle ? 15 : compact ? 13.5 : 14,
                          height: 1.2,
                          letterSpacing: -.15,
                        ),
                      ),
                      SizedBox(height: compactStyle ? 2 : cardsStyle ? 10 : 6),
                      Row(
                        children: [
                          if (threadCount > 1) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _orange.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                '$threadCount replies',
                                style: const TextStyle(
                                  color: _orange,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          Expanded(
                            child: Text(
                              mail.body.replaceAll(RegExp(r'\s+'), ' ').trim(),
                              maxLines: cardsStyle ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compactStyle ? 10 : cardsStyle ? 13 : 12,
                                color: colors.onSurfaceVariant,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (mail.starred)
                            const Padding(
                              padding: EdgeInsets.only(left: 7),
                              child: Icon(Icons.star_rounded,
                                  size: 17, color: Color(0xFFF0B74D)),
                            ),
                          if (selectedForAction)
                            const Padding(
                              padding: EdgeInsets.only(left: 7),
                              child: Icon(Icons.check_circle_rounded,
                                  size: 18, color: _orange),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!compact || _accounts.isEmpty) return tile;
    return Dismissible(
      key: ValueKey(mail.identity),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF168F79),
          borderRadius: BorderRadius.circular(17),
        ),
        child: const Icon(Icons.mark_email_read_rounded, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFE35461),
          borderRadius: BorderRadius.circular(17),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        await _actOnMail(
          mail,
          direction == DismissDirection.startToEnd ? 'read' : 'delete',
        );
        return false;
      },
      child: tile,
    );
  }

  Widget _welcome() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 124,
            height: 124,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: _orange.withValues(alpha: .16),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/parmtech-mark.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Mail, beautifully\nconnected.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Bring your domain inboxes together. Your mailbox password stays protected on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _addAccount,
            icon: const Icon(Icons.add_rounded),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Connect your first account'),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'IMAP + SMTP  ·  TLS encryption  ·  Up to 10 inboxes',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _emptyInbox() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_outlined, size: 48, color: _muted),
        const SizedBox(height: 12),
        Text(
          _error == null
              ? 'No messages in $_activeFolderName'
              : 'Mailbox unavailable',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pull down to sync your mailbox',
          style: TextStyle(color: _muted),
        ),
      ],
    ),
  );

  Widget _errorCard() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
    child: Material(
      color: const Color(0xFF42251E),
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        leading: const Icon(Icons.wifi_off_rounded, color: Color(0xFFFFAA8A)),
        title: Text(_error!, style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ),
    ),
  );

  Widget _drawer() => Drawer(
    child: SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(14, 14, 14, 17),
            padding: const EdgeInsets.all(19),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _orange.withValues(alpha: .17),
                  _sky.withValues(alpha: .075),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: _orange.withValues(alpha: .13)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.mark_email_unread_rounded, color: _orange, size: 20),
                    SizedBox(width: 8),
                    Text('PARMTECH MAIL',
                        style: TextStyle(
                          color: _orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.45,
                        )),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('Your workspace',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.8,
                    )),
                const SizedBox(height: 5),
                Text('${_accounts.length} connected accounts',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 12, 9),
            child: Text('MAILBOXES',
                style: TextStyle(
                  color: _orange, fontSize: 10,
                  fontWeight: FontWeight.w900, letterSpacing: 1.35,
                )),
          ),
          for (final folder in _folders)
            ListTile(
              leading: Icon(_folderIcon(folder)),
              title: Text(
                _folderTitle(folder),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: folder.unread > 0
                  ? Text(
                      '${folder.unread}',
                      style: const TextStyle(
                        color: _orange,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  : null,
              selected: folder.path == _folderPath,
              onTap: () {
                Navigator.pop(context);
                _selectFolder(folder);
              },
            ),
          if (_accounts.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Create folder'),
              onTap: () { Navigator.pop(context); _createFolder(); },
            ),
          const Divider(height: 25),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 12, 9),
            child: Text('ACCOUNTS',
                style: TextStyle(
                  color: _orange, fontSize: 10,
                  fontWeight: FontWeight.w900, letterSpacing: 1.35,
                )),
          ),
          for (final a in _accounts)
            ListTile(
              leading: CircleAvatar(
                radius: 17,
                backgroundColor: _orange.withValues(alpha: .18),
                child: Text(
                  a.email[0].toUpperCase(),
                  style: const TextStyle(color: _orange),
                ),
              ),
              title: Text(
                a.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _accounts.indexOf(a) == _active
                  ? const Icon(Icons.check_circle_rounded, color: _orange, size: 19)
                  : null,
              onTap: () {
                setState(() {
                  _active = _accounts.indexOf(a);
                  _folderPath = 'INBOX';
                  _messages = [];
                  _selectedMail = null;
                    _folders = const [];
                    _selectedMessageIds.clear();
                });
                Navigator.pop(context);
                _loadFolders().then((_) => _refresh());
              },
            ),
          const Divider(height: 20),
          ListTile(
            leading: const Icon(Icons.settings_rounded, color: _orange),
            title: const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.w800)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              _openSettings();
            },
          ),
          const Padding(
            padding: EdgeInsets.all(22),
            child: Text(
              'Built by ParmTech',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MailSettingsPage(
          appearance: widget.appearance,
          onAppearanceChanged: widget.onAppearanceChanged,
          accountEmails: _accounts.map((a) => a.email).toList(),
          onAddAccount: () async {
            Navigator.of(context).pop();
            await _addAccount();
          },
          onRemoveAccount: (index) async {
            Navigator.of(context).pop();
            await _removeAccount(index);
          },
          onExportBackup: () async {
            Navigator.of(context).pop();
            await _exportBackup();
          },
          onImportBackup: () async {
            Navigator.of(context).pop();
            await _importBackup();
          },
        ),
      ),
    );
  }

  Future<void> _accountPicker() async => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your accounts',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 10),
            ..._accounts.asMap().entries.map(
              (e) => ListTile(
                leading: const Icon(
                  Icons.alternate_email_rounded,
                  color: _orange,
                ),
                title: Text(e.value.email),
                trailing: e.key == _active
                    ? const Icon(Icons.check_circle, color: _orange)
                    : null,
                onTap: () {
                  setState(() {
                    _active = e.key;
                    _folderPath = 'INBOX';
                    _messages = [];
                    _selectedMail = null;
                    _folders = const [];
                    _selectedMessageIds.clear();
                  });
                  Navigator.pop(ctx);
                  _loadFolders().then((_) => _refresh());
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add an account'),
              onTap: () {
                Navigator.pop(ctx);
                _addAccount();
              },
            ),
          ],
        ),
      ),
    ),
  );

  String get _activeFolderName {
    final matching = _folders.where((f) => f.path == _folderPath);
    return matching.isEmpty ? 'Inbox' : _folderTitle(matching.first);
  }

  String _folderTitle(MailFolder folder) {
    final name = folder.name
        .split(RegExp(r'[/\\.]'))
        .last
        .replaceAll('"', '')
        .trim();
    return switch (name.toLowerCase()) {
      'inbox' => 'Inbox',
      'sent' || 'sent items' || 'sent mail' => 'Sent',
      'drafts' => 'Drafts',
      'trash' || 'deleted items' || 'deleted messages' => 'Trash',
      'junk' || 'spam' => 'Spam',
      'archive' => 'Archive',
      _ => name.isEmpty ? folder.path : name,
    };
  }

  IconData _folderIcon(MailFolder folder) =>
      switch (_folderTitle(folder).toLowerCase()) {
        'inbox' => Icons.inbox_rounded,
        'sent' => Icons.send_outlined,
        'drafts' => Icons.drafts_outlined,
        'trash' => Icons.delete_outline_rounded,
        'spam' => Icons.report_gmailerrorred_outlined,
        'archive' => Icons.archive_outlined,
        _ => Icons.folder_outlined,
      };

  Future<void> _removeAccount(int index) async {
    if (index < 0 || index >= _accounts.length) return;
    final account = _accounts[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this account?'),
        content: Text(
          'Remove ${account.email} and erase its saved password from this device?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _vault.remove(account.email);
    _lastUnreadByEmail.remove(account.id);
    if (!mounted) return;
    final wasActive = _active == index;
    final removedBeforeActive = index < _active;
    setState(() {
      _accounts.removeAt(index);
      _active = _accounts.isEmpty
          ? 0
          : wasActive
          ? (index >= _accounts.length ? _accounts.length - 1 : index)
          : removedBeforeActive
          ? _active - 1
          : _active;
      _messages = [];
      _folders = const [];
      _folderPath = 'INBOX';
      _selectedMail = null;
    });
    if (_accounts.isNotEmpty) {
      await _loadFolders();
      await _refresh();
    } else if (Platform.isAndroid) {
      await AndroidMailBackgroundSync.cancel();
      await LiveMailService.stop();
    }
  }
}

class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key});

  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class MailDetailPage extends StatelessWidget {
  const MailDetailPage({super.key, required this.message, this.conversation = const [], this.account, this.service, this.folders = const [], this.onAction, this.onMove, this.onSent});

  final MailItem message;
  final List<MailItem> conversation;
  final MailAccount? account;
  final CpanelMailService? service;
  final List<MailFolder> folders;
  final Future<void> Function(String action)? onAction;
  final Future<void> Function(MailFolder folder)? onMove;
  final Future<void> Function()? onSent;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(conversation.length > 1 ? 'Conversation (${conversation.length})' : 'Message'),
      actions: [PopupMenuButton<String>(onSelected: (action) async {
        if (action == 'move') {
          final target = await showModalBottomSheet<MailFolder>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [for (final folder in folders.where((f) => f.path != message.mailboxPath)) ListTile(leading: const Icon(Icons.folder_outlined), title: Text(folder.name), onTap: () => Navigator.pop(ctx, folder))])));
          if (target != null && onMove != null) {
            try { await onMove!(target); }
            catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not move message: $error'))); return; }
          } else if (target != null && account != null && service != null) {
            try { await service!.moveMessage(account!, message, target.path); }
            catch (error) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not move message: $error'))); return; }
          }
          if (target != null && context.mounted) Navigator.pop(context);
        } else {
          await onAction?.call(action);
          if (action == 'delete' && context.mounted) Navigator.pop(context);
        }
      }, itemBuilder: (_) => [PopupMenuItem(value: message.unread ? 'read' : 'unread', child: Text(message.unread ? 'Mark as read' : 'Mark as unread')), PopupMenuItem(value: 'star', child: Text(message.starred ? 'Remove star' : 'Add star')), const PopupMenuItem(value: 'archive', child: Text('Archive')), const PopupMenuItem(value: 'spam', child: Text('Mark as spam')), const PopupMenuItem(value: 'move', child: Text('Move to folder')), const PopupMenuItem(value: 'delete', child: Text('Delete'))])],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        children: [
          Text(
            message.subject,
            style: const TextStyle(
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w900,
              letterSpacing: -.85,
            ),
          ),
          const SizedBox(height: 20),
          if (conversation.length > 1) ...[
            for (final earlier in conversation.where((m) => m.identity != message.identity))
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  title: Text(earlier.sender, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(earlier.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(earlier.time, style: const TextStyle(fontSize: 10, color: _muted)),
                  children: [Padding(padding: const EdgeInsets.all(16), child: SelectableText(earlier.body))],
                ),
              ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: _orange.withValues(alpha: .2),
                foregroundColor: _orange,
                child: Text(
                  message.sender.trim().isEmpty
                      ? '?'
                      : message.sender.trim()[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.sender,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (message.senderAddress.isNotEmpty &&
                        message.senderAddress.toLowerCase() !=
                            message.sender.toLowerCase())
                      Text(
                        message.senderAddress,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    if (message.time.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          message.time,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Container(
            padding: const EdgeInsets.all(19),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: .45),
              ),
            ),
            child: SelectableText(
              message.body.isEmpty
                  ? 'This message has no readable text content.'
                  : message.body,
              style: const TextStyle(height: 1.65, fontSize: 14.5),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.icon(onPressed: account == null || service == null ? null : () => _compose(context, account!, service!, to: message.senderAddress, subject: message.subject.toLowerCase().startsWith('re:') ? message.subject : 'Re: ${message.subject}', body: '\n\nOn ${message.time}, ${message.sender} wrote:\n> ${message.body.replaceAll('\n', '\n> ')}', inReplyTo: message.messageId, references: message.references), icon: const Icon(Icons.reply_rounded), label: const Text('Reply')),
            OutlinedButton.icon(onPressed: account == null || service == null ? null : () => _compose(context, account!, service!, subject: 'Fwd: ${message.subject}', body: '\n\n---------- Forwarded message ----------\nFrom: ${message.senderAddress}\nDate: ${message.time}\nSubject: ${message.subject}\n\n${message.body}'), icon: const Icon(Icons.forward_rounded), label: const Text('Forward')),
            OutlinedButton.icon(onPressed: () => _print(context), icon: const Icon(Icons.print_outlined), label: const Text('Print')),
          ]),
          if (account != null && service != null) ...[
            const SizedBox(height: 18),
            InlineReplyBox(account: account!, mailService: service!, message: message, onSent: onSent),
          ],
        ],
      ),
    ),
  );

  Future<void> _compose(BuildContext context, MailAccount account, CpanelMailService service, {String to = '', String subject = '', String body = '', String? inReplyTo, String? references}) async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ComposePage(account: account, service: service, initialTo: to, initialSubject: subject, initialBody: body, inReplyTo: inReplyTo, references: references)));
    if (sent == true) await onSent?.call();
  }

  Future<void> _print(BuildContext context) async {
    try {
      await Printing.layoutPdf(onLayout: (format) async {
        final document = pw.Document();
        document.addPage(pw.MultiPage(pageFormat: format, build: (_) => [
          pw.Text(message.subject, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12), pw.Text('From: ${message.sender} <${message.senderAddress}>'),
          pw.Text('Date: ${message.time}'), pw.Divider(), pw.Text(message.body),
        ]));
        return document.save();
      });
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open print dialog: $error')));
    }
  }
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _verifyService = CpanelMailService();
  bool _hide = true;
  bool _testing = false;
  String? _connectionError;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connect account')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 18),
            const Icon(Icons.mark_email_read_rounded, size: 50, color: _orange),
            const SizedBox(height: 20),
            const Text(
              'Connect your email account',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your address and password. Your email will only be saved after a secure IMAP connection succeeds.',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _email,
              onChanged: (_) => setState(() => _connectionError = null),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@yourdomain.com',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _hide,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Email password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(
                    _hide
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _orange.withValues(alpha: 0.16)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_rounded, color: _orange, size: 23),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ParmTech Private Mail',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 5),
                        Text(
                          'Only mailboxes created on the ParmTech hosting server can sign in. '
                          'Secure IMAP and SMTP are configured automatically.',
                          style: TextStyle(fontSize: 12, color: _muted, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (_connectionError != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connection could not be verified',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      )),
                    const SizedBox(height: 8),
                    SelectableText(
                      _connectionError!,
                      style: TextStyle(
                        height: 1.45,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Check that this mailbox exists on the ParmTech hosting server '
                      'and that its password is correct. TLS errors must be fixed on the server.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              onPressed: _testing ? null : _submit,
              icon: _testing
                  ? const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_testing ? 'Testing secure connection…' : 'Verify and connect'),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Passwords are stored only in your device’s secure vault. ParmTech never receives them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!isValidMailAddress(email) || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address and password.')),
      );
      return;
    }
    setState(() {
      _testing = true;
      _connectionError = null;
    });
    try {
      final verified = await _verifyService.verify(MailAccount(
        email: email,
        password: _password.text,
        imapHost: parmTechMailServerHost,
        smtpHost: parmTechMailServerHost,
      ));
      if (mounted) Navigator.pop(context, verified);
    } catch (error) {
      if (mounted) {
        setState(() => _connectionError = friendlyMailError(error));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }
}

class ComposePage extends StatefulWidget {
  const ComposePage({super.key, required this.account, required this.service, this.initialTo = '', this.initialSubject = '', this.initialBody = '', this.inReplyTo, this.references});
  final MailAccount account;
  final CpanelMailService service;
  final String initialTo;
  final String initialSubject;
  final String initialBody;
  final String? inReplyTo;
  final String? references;
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  late final _to = TextEditingController(text: widget.initialTo);
  late final _subject = TextEditingController(text: widget.initialSubject);
  late final _body = TextEditingController(text: widget.initialBody);
  final List<OutgoingMailAttachment> _attachments = [];
  bool _pickingFiles = false;
  bool _sending = false;
  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('New message',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: -.5)),
      actions: [
        IconButton(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const CircularProgressIndicator()
              : const Icon(Icons.send_rounded, color: _orange),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: _orange.withValues(alpha: .095),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            children: [
              const Icon(Icons.alternate_email_rounded, color: _orange, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'From  ${widget.account.email}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _to,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'To',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _subject,
          decoration: const InputDecoration(labelText: 'Subject'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          minLines: 12,
          maxLines: 24,
          decoration: const InputDecoration(hintText: 'Write your message…'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _pickingFiles || _sending ? null : _pickAttachments,
            icon: const Icon(Icons.attach_file_rounded),
            label: Text(_pickingFiles ? 'Opening files…' : 'Attach files'),
          ),
        ),
        if (_attachments.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final attachment in _attachments)
                InputChip(
                  label: Text(attachment.name),
                  onDeleted: _sending
                      ? null
                      : () => setState(() => _attachments.remove(attachment)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        const Text('Attachments: 20 MB total maximum',
            style: TextStyle(color: _muted, fontSize: 11)),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send_rounded, size: 18),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Text(_sending ? 'Sending…' : 'Send message',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    ),
  );

  Future<void> _pickAttachments() async {
    setState(() => _pickingFiles = true);
    try {
      final selected = await FilePicker.pickFiles(type: FileType.any);
      if (selected.isEmpty || !mounted) return;
      final additions = <OutgoingMailAttachment>[];
      var total = _attachments.fold<int>(
        0,
        (bytes, attachment) => bytes + attachment.bytes.length,
      );
      for (final file in selected) {
        final reportedLength = file.lengthSync() ?? await file.length();
        if (reportedLength != null &&
            total + reportedLength > 20 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('20 MB total attachment limit reached.'),
            ));
          }
          break;
        }
        final data = await file.readAsBytes();
        if (data.isEmpty) continue;
        if (total + data.length > 20 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('20 MB total attachment limit reached.')),
            );
          }
          break;
        }
        total += data.length;
        additions.add(OutgoingMailAttachment(name: file.name, bytes: data));
      }
      if (mounted) setState(() => _attachments.addAll(additions));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach file: ${friendlyMailError(error)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingFiles = false);
    }
  }

  Future<void> _send() async {
    if (!isValidMailAddress(_to.text)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a valid recipient.')));
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.service.send(
        widget.account,
        to: _to.text.trim(),
        subject: _subject.text.trim(),
        body: _body.text,
        attachments: List<OutgoingMailAttachment>.of(_attachments),
        inReplyTo: widget.inReplyTo,
        references: widget.references,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMailError(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
