import 'package:flutter/material.dart';
import 'data/accounts/mail_account.dart';
import 'data/accounts/secure_account_vault.dart';
import 'data/mail/cpanel_mail_service.dart';
import 'data/notifications/mail_notifications.dart';

void main() => runApp(const ParmMailApp());

const _ink = Color(0xFF0D1012);
const _panel = Color(0xFF171B1E);
const _orange = Color(0xFF17B9F2);
const _muted = Color(0xFF99A2A6);

class ParmMailApp extends StatelessWidget {
  const ParmMailApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ParmTech Mail',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _ink,
          colorScheme: ColorScheme.fromSeed(seedColor: _orange, brightness: Brightness.dark, surface: _panel),
          appBarTheme: const AppBarTheme(backgroundColor: _ink, elevation: 0),
          inputDecorationTheme: InputDecorationTheme(
            filled: true, fillColor: _panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        home: const MailHome(),
      );
}

class MailHome extends StatefulWidget {
  const MailHome({super.key});
  @override
  State<MailHome> createState() => _MailHomeState();
}

class _MailHomeState extends State<MailHome> {
  final _vault = SecureAccountVault();
  final _service = CpanelMailService();
  final _notifications = MailNotifications();
  List<MailAccount> _accounts = [];
  List<MailItem> _messages = [];
  List<MailFolder> _folders = const [];
  int _active = 0;
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  bool _hasSynced = false;
  String _folderPath = 'INBOX';
  bool _searchOpen = false;
  final _search = TextEditingController();

  @override
  void initState() { super.initState(); _restore(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  Future<void> _restore() async {
    try { await _notifications.initialize(); } catch (_) { /* Notifications may not be available on this host OS. */ }
    try {
      final saved = await _vault.readAll();
      if (!mounted) return;
      setState(() { _accounts = saved; _loading = false; });
      if (saved.isNotEmpty) { await _loadFolders(); await _refresh(); }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Secure account storage is unavailable. ${friendlyMailError(e)}'; });
    }
  }

  Future<void> _refresh() async {
    if (_accounts.isEmpty) return;
    setState(() { _syncing = true; _error = null; });
    try {
      final items = await _service.fetchFolder(_accounts[_active], _folderPath);
      final previousUnread = _messages.where((m) => m.unread).length;
      final currentUnread = items.where((m) => m.unread).length;
      if (_folderPath.toUpperCase() == 'INBOX' && _hasSynced && currentUnread > previousUnread) {
        try { await _notifications.showNewMail(currentUnread - previousUnread); } catch (_) { /* Notification permission is optional. */ }
      }
      _hasSynced = true;
      if (mounted) setState(() => _messages = items);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyMailError(e));
    } finally { if (mounted) setState(() => _syncing = false); }
  }

  Future<void> _loadFolders() async {
    if (_accounts.isEmpty) return;
    try {
      final folders = await _service.listFolders(_accounts[_active]);
      if (mounted) setState(() {
        _folders = folders;
        if (_folderPath != 'INBOX' && !folders.any((f) => f.path == _folderPath)) _folderPath = 'INBOX';
      });
    } catch (_) { /* Keep the Inbox shortcut available if LIST is unsupported. */ }
  }

  Future<void> _selectFolder(MailFolder folder) async {
    setState(() { _folderPath = folder.path; _messages = []; _hasSynced = false; });
    await _refresh();
  }

  Future<void> _addAccount() async {
    if (_accounts.length >= SecureAccountVault.maxAccounts) {
      _notice('You can add up to 10 accounts.'); return;
    }
    final account = await Navigator.of(context).push<MailAccount>(MaterialPageRoute(builder: (_) => const AddAccountPage()));
    if (account == null || !mounted) return;
    setState(() => _syncing = true);
    try {
      final verified = await _service.verify(account);
      await _vault.add(verified);
      if (!mounted) return;
      setState(() { _accounts = [..._accounts.where((a) => a.id != verified.id), verified]; _active = _accounts.indexWhere((a) => a.id == verified.id); _messages = []; _hasSynced = false; });
      await _loadFolders();
      await _refresh();
    } catch (e) { if (mounted) _notice(friendlyMailError(e)); }
    finally { if (mounted) setState(() => _syncing = false); }
  }

  Future<void> _compose() async {
    if (_accounts.isEmpty) { await _addAccount(); return; }
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ComposePage(account: _accounts[_active], service: _service)));
    if (sent == true) await _refresh();
  }

  Future<void> _open(MailItem message) async => showModalBottomSheet<void>(
        context: context, isScrollControlled: true, showDragHandle: true,
        builder: (context) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message.subject, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10), Text(message.sender, style: const TextStyle(color: _muted)),
            const Divider(height: 28), SelectableText(message.body.isEmpty ? 'This message has no plain-text preview.' : message.body, style: const TextStyle(height: 1.55)),
          ]),
        )),
      );

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final account = _accounts.isEmpty ? null : _accounts[_active];
    return Scaffold(
      drawer: _drawer(),
      appBar: AppBar(
        titleSpacing: 8,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PARMTECH  /  MAIL', style: TextStyle(color: _orange, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.8)),
          Text(account?.email ?? 'Your inbox', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(onPressed: _syncing ? null : _refresh, tooltip: 'Sync', icon: _syncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync_rounded)),
          IconButton(onPressed: () => setState(() => _searchOpen = !_searchOpen), tooltip: 'Search', icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded)),
          IconButton(onPressed: _accountPicker, tooltip: 'Accounts', icon: const Icon(Icons.account_circle_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        _header(account),
        if (_error != null) _errorCard(),
        if (_searchOpen && _accounts.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 10), child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Search sender, subject or message', prefixIcon: Icon(Icons.search_rounded)))),
        Expanded(child: _accounts.isEmpty ? _welcome() : _messages.isEmpty && !_syncing ? _emptyInbox() : _messageList()),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _compose, backgroundColor: _orange, foregroundColor: Colors.black, icon: const Icon(Icons.edit_rounded), label: const Text('Compose', style: TextStyle(fontWeight: FontWeight.w800))),
    );
  }

  Widget _header(MailAccount? account) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(_activeFolderName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.7))), if (account != null) _connectionPill()]),
      const SizedBox(height: 14),
      if (_folders.isNotEmpty) SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _folders.map((f) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(_folderTitle(f)), selected: f.path == _folderPath, onSelected: (_) => _selectFolder(f)))).toList()))
      else const Text('Your latest messages, synced securely', style: TextStyle(color: _muted, fontSize: 12)),
    ]),
  );

  Widget _connectionPill() => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: const Color(0xFF17372C), borderRadius: BorderRadius.circular(30)), child: const Row(children: [Icon(Icons.lock_rounded, size: 13, color: Color(0xFF72D6A6)), SizedBox(width: 5), Text('SECURE', style: TextStyle(color: Color(0xFF8AE0B4), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .7))]));

  Widget _messageList() {
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty ? _messages : _messages.where((m) => '${m.sender} ${m.subject} ${m.body}'.toLowerCase().contains(query)).toList();
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: RefreshIndicator(onRefresh: _refresh, child: ListView.separated(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), itemCount: visible.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) => _tile(visible[index])))));
  }

  Widget _tile(MailItem mail) => Material(color: _panel, borderRadius: BorderRadius.circular(20), child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => _open(mail), child: Padding(padding: const EdgeInsets.all(15), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    CircleAvatar(radius: 22, backgroundColor: mail.unread ? const Color(0xFF633522) : const Color(0xFF30363A), child: Text(mail.sender.trim().isEmpty ? '?' : mail.sender.trim()[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
    const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(mail.sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: mail.unread ? FontWeight.w800 : FontWeight.w600))), Text(mail.time, style: const TextStyle(color: _muted, fontSize: 11))]),
      const SizedBox(height: 5), Text(mail.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: mail.unread ? FontWeight.w800 : FontWeight.w500)),
      const SizedBox(height: 4), Text(mail.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
    ])), const SizedBox(width: 8), Icon(mail.unread ? Icons.circle : Icons.star_border_rounded, size: mail.unread ? 9 : 19, color: mail.unread ? _orange : Colors.white54),
  ]))));

  Widget _welcome() => Center(child: SingleChildScrollView(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 124, height: 124, padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: _orange.withOpacity(.16), blurRadius: 34, spreadRadius: 2)]), child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/parmtech-mark.png', fit: BoxFit.cover)),
    const SizedBox(height: 28), const Text('Mail, beautifully\nconnected.', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1.1)),
    const SizedBox(height: 12), const Text('Bring your domain inboxes together. Your mailbox password stays protected on this device.', textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.5)),
    const SizedBox(height: 24), FilledButton.icon(onPressed: _addAccount, icon: const Icon(Icons.add_rounded), label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Connect your first account'))),
    const SizedBox(height: 14), const Text('IMAP + SMTP  ·  TLS encryption  ·  Up to 10 inboxes', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 11)),
  ])));

  Widget _emptyInbox() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.inbox_outlined, size: 48, color: _muted), const SizedBox(height: 12), Text(_error == null ? 'No messages in $_activeFolderName' : 'Mailbox unavailable', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 6), const Text('Pull down to sync your mailbox', style: TextStyle(color: _muted))]));

  Widget _errorCard() => Padding(padding: const EdgeInsets.fromLTRB(18, 2, 18, 8), child: Material(color: const Color(0xFF42251E), borderRadius: BorderRadius.circular(14), child: ListTile(leading: const Icon(Icons.wifi_off_rounded, color: Color(0xFFFFAA8A)), title: Text(_error!, style: const TextStyle(fontSize: 12)), trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)))));

  Widget _drawer() => Drawer(child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(22, 22, 22, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('PARMTECH', style: TextStyle(color: _orange, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2)), const SizedBox(height: 4), const Text('Your mail', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)), Text('${_accounts.length} of 10 accounts', style: const TextStyle(color: _muted))]),
    const Divider(),
    for (final folder in _folders) ListTile(leading: Icon(_folderIcon(folder)), title: Text(_folderTitle(folder), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: folder.unread > 0 ? Text('${folder.unread}', style: const TextStyle(color: _orange, fontWeight: FontWeight.w800)) : null, selected: folder.path == _folderPath, onTap: () { Navigator.pop(context); _selectFolder(folder); }),
    const Divider(),
    for (final a in _accounts) ListTile(leading: CircleAvatar(radius: 17, backgroundColor: _orange.withOpacity(.18), child: Text(a.email[0].toUpperCase(), style: const TextStyle(color: _orange))), title: Text(a.email, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: 'Remove account', icon: const Icon(Icons.logout_rounded, size: 18), onPressed: () { final index = _accounts.indexOf(a); Navigator.pop(context); _removeAccount(index); }), onTap: () { setState(() { _active = _accounts.indexOf(a); _folderPath = 'INBOX'; _hasSynced = false; _messages = []; }); Navigator.pop(context); _loadFolders().then((_) => _refresh()); }),
    ListTile(leading: const Icon(Icons.add_circle_outline), title: const Text('Add another account'), onTap: () { Navigator.pop(context); _addAccount(); }),
    ListTile(leading: const Icon(Icons.notifications_active_outlined), title: const Text('Enable new-mail alerts'), onTap: () async { Navigator.pop(context); try { final allowed = await _notifications.requestPermission(); if (mounted) _notice(allowed ? 'New-mail alerts are enabled for inbox syncs.' : 'Notification permission was not granted.'); } catch (e) { if (mounted) _notice(friendlyMailError(e)); } }),
    const Spacer(), const Padding(padding: EdgeInsets.all(22), child: Text('Built by ParmTech', style: TextStyle(color: _muted, fontSize: 12))),
  ])));

  Future<void> _accountPicker() async => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [const Align(alignment: Alignment.centerLeft, child: Text('Your accounts', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))), const SizedBox(height: 10), ..._accounts.asMap().entries.map((e) => ListTile(leading: const Icon(Icons.alternate_email_rounded, color: _orange), title: Text(e.value.email), trailing: e.key == _active ? const Icon(Icons.check_circle, color: _orange) : null, onTap: () { setState(() { _active = e.key; _folderPath = 'INBOX'; _hasSynced = false; _messages = []; }); Navigator.pop(ctx); _loadFolders().then((_) => _refresh()); })), ListTile(leading: const Icon(Icons.add), title: const Text('Add an account'), onTap: () { Navigator.pop(ctx); _addAccount(); })]))));

  String get _activeFolderName { final matching = _folders.where((f) => f.path == _folderPath); return matching.isEmpty ? 'Inbox' : _folderTitle(matching.first); }
  String _folderTitle(MailFolder folder) {
    final name = folder.name.split('/').last.replaceAll('"', '').trim();
    return switch (name.toLowerCase()) { 'inbox' => 'Inbox', 'sent' || 'sent items' || 'sent mail' => 'Sent', 'drafts' => 'Drafts', 'trash' || 'deleted items' || 'deleted messages' => 'Trash', 'junk' || 'spam' => 'Spam', 'archive' => 'Archive', _ => name.isEmpty ? folder.path : name };
  }
  IconData _folderIcon(MailFolder folder) => switch (_folderTitle(folder).toLowerCase()) { 'inbox' => Icons.inbox_rounded, 'sent' => Icons.send_outlined, 'drafts' => Icons.drafts_outlined, 'trash' => Icons.delete_outline_rounded, 'spam' => Icons.report_gmailerrorred_outlined, 'archive' => Icons.archive_outlined, _ => Icons.folder_outlined };

  Future<void> _removeAccount(int index) async {
    if (index < 0 || index >= _accounts.length) return;
    final account = _accounts[index];
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Remove this account?'), content: Text('Remove ${account.email} and erase its saved password from this device?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove'))]));
    if (confirmed != true) return;
    await _vault.remove(account.email);
    if (!mounted) return;
    final wasActive = _active == index;
    final removedBeforeActive = index < _active;
    setState(() {
      _accounts.removeAt(index);
      _active = _accounts.isEmpty ? 0 : wasActive ? (index >= _accounts.length ? _accounts.length - 1 : index) : removedBeforeActive ? _active - 1 : _active;
      _messages = []; _folders = const []; _folderPath = 'INBOX'; _hasSynced = false;
    });
    if (_accounts.isNotEmpty) { await _loadFolders(); await _refresh(); }
  }
}

class AddAccountPage extends StatefulWidget { const AddAccountPage({super.key}); @override State<AddAccountPage> createState() => _AddAccountPageState(); }
class _AddAccountPageState extends State<AddAccountPage> {
  final _email = TextEditingController(); final _password = TextEditingController(); bool _hide = true;
  @override void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Connect account')), body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(padding: const EdgeInsets.all(24), children: [
    const SizedBox(height: 18), const Icon(Icons.mark_email_read_rounded, size: 50, color: _orange), const SizedBox(height: 20), const Text('Add your domain email', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.7)), const SizedBox(height: 8), const Text('We’ll find secure IMAP settings and test the sign-in before saving it.', style: TextStyle(color: _muted, height: 1.5)), const SizedBox(height: 28),
    TextField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email address', hintText: 'you@yourdomain.com', prefixIcon: Icon(Icons.alternate_email_rounded))), const SizedBox(height: 14),
    TextField(controller: _password, obscureText: _hide, autofillHints: const [AutofillHints.password], decoration: InputDecoration(labelText: 'Email password', prefixIcon: const Icon(Icons.lock_outline_rounded), suffixIcon: IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined)))), const SizedBox(height: 22),
    FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.lock_rounded), label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Verify and connect'))), const SizedBox(height: 14), const Text('Passwords are stored only in your device’s secure vault. ParmTech never receives them.', textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 12, height: 1.4)),
  ]))));
  void _submit() { final email = _email.text.trim(); final parts = email.split('@'); if (parts.length != 2 || parts.first.isEmpty || !parts.last.contains('.') || _password.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid email address and password.'))); return; } Navigator.pop(context, MailAccount(email: email, password: _password.text, imapHost: cPanelHostCandidates(email).first.host, smtpHost: cPanelHostCandidates(email).first.host)); }
}

class ComposePage extends StatefulWidget { const ComposePage({super.key, required this.account, required this.service}); final MailAccount account; final CpanelMailService service; @override State<ComposePage> createState() => _ComposePageState(); }
class _ComposePageState extends State<ComposePage> {
  final _to = TextEditingController(); final _subject = TextEditingController(); final _body = TextEditingController(); bool _sending = false;
  @override void dispose() { _to.dispose(); _subject.dispose(); _body.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('New message'), actions: [IconButton(onPressed: _sending ? null : _send, icon: _sending ? const CircularProgressIndicator() : const Icon(Icons.send_rounded, color: _orange))]), body: ListView(padding: const EdgeInsets.all(18), children: [Text('From  ${widget.account.email}', style: const TextStyle(color: _muted)), const SizedBox(height: 14), TextField(controller: _to, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'To', prefixIcon: Icon(Icons.person_outline_rounded))), const SizedBox(height: 12), TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject')), const SizedBox(height: 12), TextField(controller: _body, minLines: 12, maxLines: 24, decoration: const InputDecoration(hintText: 'Write your message…'))]));
  Future<void> _send() async { if (!_to.text.contains('@')) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid recipient.'))); return; } setState(() => _sending = true); try { await widget.service.send(widget.account, to: _to.text.trim(), subject: _subject.text.trim(), body: _body.text); if (mounted) Navigator.pop(context, true); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMailError(e)))); } finally { if (mounted) setState(() => _sending = false); } }
}
