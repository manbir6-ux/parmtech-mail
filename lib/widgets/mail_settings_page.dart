import 'package:flutter/material.dart';

class MailSettingsPage extends StatelessWidget {
  const MailSettingsPage({
    super.key,
    required this.darkTheme,
    required this.onThemeToggle,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onAddAccount,
    required this.accountEmails,
    required this.onRemoveAccount,
  });

  final bool darkTheme;
  final VoidCallback onThemeToggle;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onImportBackup;
  final Future<void> Function() onAddAccount;
  final List<String> accountEmails;
  final Future<void> Function(int index) onRemoveAccount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
        centerTitle: false,
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
                Text('A cleaner, more focused inbox.',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 27),
          const _SectionTitle('Appearance'),
          _SettingsPanel(children: [
            ListTile(
              leading: Icon(darkTheme
                  ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
              title: const Text('Dark appearance'),
              subtitle: Text(darkTheme ? 'On' : 'Off'),
              trailing: Switch(
                value: darkTheme,
                onChanged: (_) => onThemeToggle(),
              ),
              onTap: onThemeToggle,
            ),
          ]),
          const SizedBox(height: 25),
          const _SectionTitle('Accounts'),
          _SettingsPanel(children: [
            for (var i = 0; i < accountEmails.length; i++)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Text(accountEmails[i][0].toUpperCase(),
                      style: TextStyle(color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800)),
                ),
                title: Text(accountEmails[i],
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Remove account',
                  onPressed: () => onRemoveAccount(i),
                  icon: const Icon(Icons.logout_rounded, size: 19),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_rounded),
              title: const Text('Connect another account'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onAddAccount,
            ),
          ]),
          const SizedBox(height: 25),
          const _SectionTitle('Backup & restore'),
          _SettingsPanel(children: [
            ListTile(
              leading: const Icon(Icons.lock_clock_rounded),
              title: const Text('Export encrypted backup'),
              subtitle: const Text('Save your accounts and offline email cache'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onExportBackup,
            ),
            const Divider(height: 1, indent: 58),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: const Text('Import backup'),
              subtitle: const Text('Restore a password-protected .ptmail file'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onImportBackup,
            ),
          ]),
          const SizedBox(height: 25),
          const _SectionTitle('Mail delivery'),
          const _SettingsPanel(children: [
            ListTile(
              leading: Icon(Icons.notifications_active_outlined),
              title: Text('Automatic mail checking'),
              subtitle: Text(
                'Enabled by default. Android notification permission is '
                'required for alerts. Delivery times depend on device '
                'battery policies and network access.',
              ),
            ),
          ]),
          const SizedBox(height: 24),
          const Center(
            child: Text('Built by ParmTech · v0.3.1',
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
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(children: children),
    );
  }
}
