import 'package:flutter/material.dart';

import '../data/appearance/mail_appearance.dart';

class MailSettingsPage extends StatefulWidget {
  const MailSettingsPage({
    super.key,
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onAddAccount,
    required this.accountEmails,
    required this.onRemoveAccount,
  });

  final MailAppearance appearance;
  final ValueChanged<MailAppearance> onAppearanceChanged;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onImportBackup;
  final Future<void> Function() onAddAccount;
  final List<String> accountEmails;
  final Future<void> Function(int index) onRemoveAccount;

  @override
  State<MailSettingsPage> createState() => _MailSettingsPageState();
}

class _MailSettingsPageState extends State<MailSettingsPage> {
  late MailAppearance _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.appearance;
  }

  @override
  void didUpdateWidget(covariant MailSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appearance != oldWidget.appearance) {
      _selected = widget.appearance;
    }
  }

  void _change(MailAppearance prefs) {
    if (_selected.palette == prefs.palette &&
        _selected.font == prefs.font &&
        _selected.layout == prefs.layout) return;
    setState(() => _selected = prefs);
    widget.onAppearanceChanged(prefs);
  }

  Widget _paletteChoice(MailPalette option) {
    final selected = _selected.palette == option;
    return ChoiceChip(
      key: Key('palette-${option.name}'),
      selected: selected,
      showCheckmark: true,
      avatar: CircleAvatar(radius: 9, backgroundColor: option.accent),
      label: Text(option.label),
      onSelected: (_) => _change(_selected.copyWith(palette: option)),
    );
  }

  Widget _fontChoice(MailFont font) => ChoiceChip(
    key: Key('font-${font.name}'),
    selected: font == _selected.font,
    label: Text(
      font.label,
      style: TextStyle(fontFamily: font.family, fontSize: 13),
    ),
    onSelected: (_) => _change(_selected.copyWith(font: font)),
  );

  Widget _layoutChoice(MailLayout layout) => ChoiceChip(
    key: Key('layout-${layout.name}'),
    selected: layout == _selected.layout,
    label: Text(layout.label),
    onSelected: (_) => _change(_selected.copyWith(layout: layout)),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                colors.primary,
                Color.lerp(colors.primary, colors.tertiary, .62)!,
              ]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 31),
                SizedBox(height: 15),
                Text('ParmTech Mail',
                    style: TextStyle(color: Colors.white, fontSize: 25,
                        fontWeight: FontWeight.w900, letterSpacing: -.7)),
                SizedBox(height: 4),
                Text('Your inbox, your style.',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const _SectionTitle('6 color themes'),
          _SettingsPanel(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Light', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  Wrap(spacing: 7, runSpacing: 7, children: [
                    for (final option in MailPalette.values.where((p) => !p.isDark))
                      _paletteChoice(option),
                  ]),
                  const SizedBox(height: 15),
                  const Text('Dark', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  Wrap(spacing: 7, runSpacing: 7, children: [
                    for (final option in MailPalette.values.where((p) => p.isDark))
                      _paletteChoice(option),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 22),
          const _SectionTitle('6 font styles'),
          _SettingsPanel(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 7, runSpacing: 7, children: [
                    for (final font in MailFont.values) _fontChoice(font),
                  ]),
                  const SizedBox(height: 12),
                  Text('This is how your inbox will look.',
                    style: TextStyle(
                      fontFamily: _selected.font.family,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text('Offline system fonts; available without a data connection.',
                      style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 22),
          const _SectionTitle('3 inbox layouts'),
          _SettingsPanel(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 7, runSpacing: 7, children: [
                    for (final layout in MailLayout.values)
                      _layoutChoice(layout),
                  ]),
                  const SizedBox(height: 9),
                  Text(_selected.layout.description,
                      style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Private mail accounts'),
          _SettingsPanel(children: [
            for (var i = 0; i < widget.accountEmails.length; i++)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Text(widget.accountEmails[i][0].toUpperCase(),
                      style: TextStyle(color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800)),
                ),
                title: Text(widget.accountEmails[i],
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Remove account',
                  onPressed: () => widget.onRemoveAccount(i),
                  icon: const Icon(Icons.logout_rounded, size: 19),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('Connect another account'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: widget.onAddAccount,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 13),
              child: Text('Only mailboxes on the private ParmTech hosting server are supported.',
                  style: TextStyle(fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 24),
          const _SectionTitle('Backup & restore'),
          _SettingsPanel(children: [
            ListTile(
              leading: const Icon(Icons.lock_clock_rounded),
              title: const Text('Export encrypted backup'),
              subtitle: const Text('Save accounts and offline email cache'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: widget.onExportBackup,
            ),
            const Divider(height: 1, indent: 58),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: const Text('Import backup'),
              subtitle: const Text('Restore a password-protected .ptmail file'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: widget.onImportBackup,
            ),
          ]),
          const SizedBox(height: 22),
          const Center(
            child: Text('Built by ParmTech',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.25,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      clipBehavior: Clip.antiAlias,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(children: children),
    );
  }
}
