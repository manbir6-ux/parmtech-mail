import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';
import 'data/background/mail_background_sync.dart';
import 'data/accounts/mail_account.dart';
import 'data/accounts/secure_account_vault.dart';
import 'data/mail/cpanel_mail_service.dart';
import 'data/notifications/mail_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) await windowManager.ensureInitialized();
  if (Platform.isAndroid) {
    try {
      await AndroidMailBackgroundSync.initialize();
    } catch (_) {
      // A scheduler issue should not prevent the mailbox UI from opening.
    }
  }
  runApp(const ParmMailApp());
}

bool _darkTheme = true;
Color get _ink =>
    _darkTheme ? const Color(0xFF101719) : const Color(0xFFF3F7F6);
Color get _panel => _darkTheme ? const Color(0xFF192224) : Colors.white;
const _orange = Color(0xFF16B89A);
const _muted = Color(0xFF788681);

class ParmMailApp extends StatefulWidget {
  const ParmMailApp({super.key});

  @override
  State<ParmMailApp> createState() => _ParmMailAppState();
}

class _ParmMailAppState extends State<ParmMailApp> {
  void _toggleTheme() => setState(() {
    _darkTheme = !_darkTheme;
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Parmtech Mail',
    debugShowCheckedModeBanner: false,
    themeMode: _darkTheme ? ThemeMode.dark : ThemeMode.light,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _orange,
        brightness: Brightness.light,
        surface: _panel,
      ),
      appBarTheme: AppBarTheme(backgroundColor: _ink, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _orange,
        brightness: Brightness.dark,
        surface: _panel,
      ),
      appBarTheme: AppBarTheme(backgroundColor: _ink, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: MailHome(onThemeToggle: _toggleTheme),
  );
}

class MailHome extends StatefulWidget {
  const MailHome({super.key, required this.onThemeToggle});
  final VoidCallback onThemeToggle;
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
    if (Platform.isAndroid) {
      try {
        await AndroidMailBackgroundSync.cancel();
      } catch (_) {}
    }
    if (!_quitting && mounted && _accounts.isNotEmpty) {
      _autoSyncTimer = Timer.periodic(
        const Duration(minutes: 5),
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
      if (!mounted) return;
      setState(() {
        _accounts = saved;
        _loading = false;
      });
      if (saved.isNotEmpty) {
        await _loadFolders();
        await _refresh();
        unawaited(_seedUnreadCounts());
      } else if (Platform.isAndroid) {
        try {
          await AndroidMailBackgroundSync.cancel();
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
    try {
      final items = await _service.fetchFolder(account, folderPath);
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
      if (isInbox) {
        _lastUnreadByEmail[account.id] = currentUnread;
      }
      if (mounted &&
          _accounts.isNotEmpty &&
          _accounts[_active].id == account.id &&
          _folderPath == folderPath) {
        setState(() {
          _messages = items;
          if (_selectedMail == null || !items.contains(_selectedMail)) {
            _selectedMail = items.isEmpty ? null : items.first;
          }
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

  Future<void> _autoCheckInboxes() async {
    if (!mounted || _accounts.isEmpty || _syncing) return;
    final accounts = List<MailAccount>.of(_accounts);
    final activeAccountId = _accounts[_active].id;
    setState(() => _syncing = true);
    try {
      for (final account in accounts) {
        try {
          final isActiveInbox = account.id == activeAccountId &&
              _folderPath.toUpperCase() == 'INBOX';
          final items = isActiveInbox ? await _service.fetchInbox(account) : null;
          final unread = await _service.countUnread(account);
          if (!_accounts.any((saved) => saved.id == account.id)) continue;
          final previous = _lastUnreadByEmail[account.id];
          _lastUnreadByEmail[account.id] = unread;
          if (previous != null && unread > previous) {
            try {
              await _notifications.showNewMail(unread - previous);
            } catch (_) {}
          }
          if (items != null &&
              mounted &&
              _accounts.isNotEmpty &&
              _accounts[_active].id == account.id &&
              _folderPath.toUpperCase() == 'INBOX') {
            setState(() {
              _messages = items;
              if (_selectedMail == null || !items.contains(_selectedMail)) {
                _selectedMail = items.isEmpty ? null : items.first;
              }
            });
          }
        } catch (_) {
          // A temporary connection failure is retried at the next poll.
        }
      }
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
      _lastUnreadByEmail.addAll(counts);
      await _vault.writeUnreadCounts(counts);
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
      final verified = await _service.verify(account);
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

  Future<void> _open(MailItem message) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MailDetailPage(message: message),
      ),
    );
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
          IconButton(
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
          IconButton(
            onPressed: widget.onThemeToggle,
            tooltip: _darkTheme
                ? 'Switch to light mode'
                : 'Switch to dark mode',
            icon: Icon(
              _darkTheme ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: _orange,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.edit_rounded),
        label: const Text(
          'Compose',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _desktopLayout(MailAccount? account) {
    final query = _search.text.trim().toLowerCase();
    final visibleMessages = query.isEmpty
        ? _messages
        : _messages
              .where(
                (message) =>
                    '${message.sender} ${message.subject} ${message.body}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList();
    final selected =
        _selectedMail != null && visibleMessages.contains(_selectedMail)
        ? _selectedMail
        : (visibleMessages.isEmpty ? null : visibleMessages.first);

    return Row(
      children: [
        Container(
          width: 232,
          decoration: BoxDecoration(
            color: _darkTheme
                ? const Color(0xFF141D1F)
                : const Color(0xFFEAF1EF),
            border: Border(
              right: BorderSide(
                color: _darkTheme ? Colors.white10 : Colors.black12,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.mark_email_unread_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Text(
                          'Parmtech Mail',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: FilledButton.icon(
                    onPressed: _compose,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Compose'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _desktopNavTile(
                  Icons.inbox_rounded,
                  'Inbox',
                  _folderPath.toUpperCase() == 'INBOX',
                  () {
                    setState(() {
                      _folderPath = 'INBOX';
                      _messages = [];
                    });
                    _refresh();
                  },
                ),
                for (final folder
                    in _folders
                        .where((folder) => folder.path.toUpperCase() != 'INBOX')
                        .take(8))
                  _desktopNavTile(
                    _folderIcon(folder),
                    _folderTitle(folder),
                    folder.path == _folderPath,
                    () => _selectFolder(folder),
                    trailing: folder.unread > 0 ? '${folder.unread}' : null,
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(
                    'ACCOUNTS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: _muted,
                    ),
                  ),
                ),
                for (final mailbox in _accounts)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: _orange.withValues(alpha: .16),
                      child: Text(
                        mailbox.email[0].toUpperCase(),
                        style: const TextStyle(
                          color: _orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    title: Text(
                      mailbox.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: mailbox.email == account?.email,
                    onTap: () {
                      setState(() {
                        _active = _accounts.indexOf(mailbox);
                        _folderPath = 'INBOX';
                        _messages = [];
                        _selectedMail = null;
                      });
                      _loadFolders().then((_) => _refresh());
                    },
                  ),
                const Spacer(),
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Add account'),
                  onTap: _addAccount,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Text(
                    'Secure IMAP  ·  Up to 10 accounts',
                    style: TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeFolderName,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            account?.email ?? '',
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search mail',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: _syncing ? null : _refresh,
                      tooltip: 'Check mail now',
                      icon: _syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                    ),
                  ],
                ),
              ),
              if (_error != null) _errorCard(),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 390,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: _darkTheme
                                  ? Colors.white10
                                  : Colors.black12,
                            ),
                          ),
                        ),
                        child: _syncing && _messages.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : visibleMessages.isEmpty
                            ? _emptyInbox()
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  6,
                                  12,
                                  18,
                                ),
                                itemCount: visibleMessages.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 7),
                                itemBuilder: (context, index) {
                                  final mail = visibleMessages[index];
                                  return _tile(
                                    mail,
                                    selected: mail == selected,
                                    onTap: () =>
                                        setState(() => _selectedMail = mail),
                                  );
                                },
                              ),
                      ),
                    ),
                    Expanded(child: _desktopMessagePreview(selected)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                child: Text(
                  _syncing
                      ? 'Checking for new mail…'
                      : 'Auto-checks every 5 minutes  ·  ${_messages.length} messages loaded',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _desktopNavTile(
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap, {
    String? trailing,
  }) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
    leading: Icon(icon, size: 19, color: selected ? _orange : _muted),
    title: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
    trailing: trailing == null
        ? null
        : Text(
            trailing,
            style: const TextStyle(
              color: _orange,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
    selected: selected,
    selectedTileColor: _orange.withValues(alpha: .1),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onTap: onTap,
  );

  Widget _desktopMessagePreview(MailItem? mail) {
    if (mail == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined, size: 52, color: _muted),
            SizedBox(height: 14),
            Text(
              'Select a message to read',
              style: TextStyle(color: _muted, fontSize: 15),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 28, 34, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  mail.subject,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _orange.withValues(alpha: .2),
                foregroundColor: _orange,
                child: Text(
                  mail.sender.trim().isEmpty
                      ? '?'
                      : mail.sender.trim()[0].toUpperCase(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mail.sender,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (mail.senderAddress.isNotEmpty &&
                        mail.senderAddress.toLowerCase() !=
                            mail.sender.toLowerCase())
                      Text(
                        mail.senderAddress,
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    Text(
                      mail.time.isEmpty ? 'From your mailbox' : mail.time,
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                mail.body.isEmpty
                    ? 'This message has no plain-text preview.'
                    : mail.body,
                style: const TextStyle(height: 1.65, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(MailAccount? account) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _activeFolderName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.7,
                ),
              ),
            ),
            if (account != null) _connectionPill(),
          ],
        ),
        const SizedBox(height: 14),
        if (_folders.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _folders
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_folderTitle(f)),
                        selected: f.path == _folderPath,
                        onSelected: (_) => _selectFolder(f),
                      ),
                    ),
                  )
                  .toList(),
            ),
          )
        else
          const Text(
            'Your latest messages, synced securely',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
      ],
    ),
  );

  Widget _connectionPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF17372C),
      borderRadius: BorderRadius.circular(30),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock_rounded, size: 13, color: Color(0xFF72D6A6)),
        SizedBox(width: 5),
        Text(
          'SECURE',
          style: TextStyle(
            color: Color(0xFF8AE0B4),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: .7,
          ),
        ),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 100),
            itemCount: visible.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 70,
              color: _darkTheme ? Colors.white10 : Colors.black12,
            ),
            itemBuilder: (context, index) => _tile(
              visible[index],
              compact: true,
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
    VoidCallback? onTap,
  }) =>
      Material(
        color: compact
            ? Colors.transparent
            : selected
            ? _orange.withValues(alpha: .13)
            : _panel,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap ?? () => _open(mail),
          child: Semantics(
            button: true,
            label: 'Email from ${mail.sender}. ${mail.subject}. ${mail.time}',
            child: Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 12)
                : const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: compact ? 20 : 22,
                  backgroundColor: mail.unread
                      ? const Color(0xFF633522)
                      : const Color(0xFF30363A),
                  child: Text(
                    mail.sender.trim().isEmpty
                        ? '?'
                        : mail.sender.trim()[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 13),
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
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: compact ? 14 : null,
                              ),
                            ),
                          ),
                          Text(
                            mail.time,
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        mail.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: mail.unread
                              ? FontWeight.w800
                              : FontWeight.w500,
                          fontSize: compact ? 14 : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mail.body,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (mail.unread)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 9, color: _orange),
                  ),
              ],
            ),
          ),
          ),
        ),
      );

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PARMTECH',
                  style: TextStyle(
                    color: _orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your mail',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),
                Text(
                  '${_accounts.length} of 10 accounts',
                  style: const TextStyle(color: _muted),
                ),
              ],
            ),
          ),
          const Divider(),
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
          const Divider(),
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
              trailing: IconButton(
                tooltip: 'Remove account',
                icon: const Icon(Icons.logout_rounded, size: 18),
                onPressed: () {
                  final index = _accounts.indexOf(a);
                  Navigator.pop(context);
                  _removeAccount(index);
                },
              ),
              onTap: () {
                setState(() {
                  _active = _accounts.indexOf(a);
                  _folderPath = 'INBOX';
                  _messages = [];
                  _selectedMail = null;
                });
                Navigator.pop(context);
                _loadFolders().then((_) => _refresh());
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Add another account'),
            onTap: () {
              Navigator.pop(context);
              _addAccount();
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Enable new-mail alerts'),
            onTap: () async {
              Navigator.pop(context);
              try {
                final allowed = await _notifications.requestPermission();
                if (mounted) {
                  _notice(
                    allowed
                        ? Platform.isAndroid
                              ? 'Alerts are on. Android checks for new mail in the background when the system allows.'
                              : 'New-mail alerts are enabled for inbox syncs.'
                        : 'Notification permission was not granted.',
                  );
                }
              } catch (e) {
                if (mounted) _notice(friendlyMailError(e));
              }
            },
          ),
          const Spacer(),
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

  Future<void> _accountPicker() async => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
    }
  }
}

class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key});
  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class MailDetailPage extends StatelessWidget {
  const MailDetailPage({super.key, required this.message});

  final MailItem message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Message')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        children: [
          Text(
            message.subject,
            style: const TextStyle(
              fontSize: 25,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 20),
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
          SelectableText(
            message.body.isEmpty
                ? 'This message has no readable text content.'
                : message.body,
            style: const TextStyle(height: 1.6, fontSize: 15),
          ),
        ],
      ),
    ),
  );
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
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
              'Add your domain email',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'We’ll find secure IMAP settings and test the sign-in before saving it.',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _email,
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
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.lock_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Verify and connect'),
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
  void _submit() {
    final email = _email.text.trim();
    if (!isValidMailAddress(email) || _password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid email address and password.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      MailAccount(
        email: email,
        password: _password.text,
        imapHost: cPanelHostCandidates(email).first.host,
        smtpHost: cPanelHostCandidates(email).first.host,
      ),
    );
  }
}

class ComposePage extends StatefulWidget {
  const ComposePage({super.key, required this.account, required this.service});
  final MailAccount account;
  final CpanelMailService service;
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
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
      title: const Text('New message'),
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
        Text(
          'From  ${widget.account.email}',
          style: const TextStyle(color: _muted),
        ),
        const SizedBox(height: 14),
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
      ],
    ),
  );
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
