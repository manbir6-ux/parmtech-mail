class MailAccount {
  static const int imapPort = 993;
  static const int smtpPort = 465;

  const MailAccount({
    required this.email,
    required this.password,
    required this.imapHost,
    required this.smtpHost,
    this.displayName = '',
    this.useCustomServer = false,
  });

  final String email;
  final String password;
  final String imapHost;
  final String smtpHost;
  final String displayName;
  /// The user entered the server host(s) from their provider's TLS settings.
  /// Do not override a manually chosen host with unsafe guesses.
  final bool useCustomServer;

  String get id => email.trim().toLowerCase();

  Map<String, Object?> toJson() => {
    'email': email,
    'password': password,
    'imapHost': imapHost,
    'smtpHost': smtpHost,
    'displayName': displayName,
    'useCustomServer': useCustomServer,
  };

  factory MailAccount.fromJson(Map<String, dynamic> json) => MailAccount(
    email: json['email'] as String,
    password: json['password'] as String,
    imapHost: json['imapHost'] as String,
    smtpHost: json['smtpHost'] as String,
    displayName: (json['displayName'] as String?) ?? '',
    useCustomServer: (json['useCustomServer'] as bool?) ?? false,
  );
}

/// Reuses the TLS hostnames of an account already verified on this device.
/// An explicit user choice is required before applying these to another
/// mailbox, since unrelated email domains may use different providers.
class ReusableMailServer {
  const ReusableMailServer({
    required this.sourceEmail,
    required this.imapHost,
    required this.smtpHost,
  });

  final String sourceEmail;
  final String imapHost;
  final String smtpHost;
}

/// Deduplicated configurations from connected accounts. No passwords or
/// inferred domain ownership are copied.
List<ReusableMailServer> reusableMailServers(Iterable<MailAccount> accounts) {
  final seen = <String>{};
  final servers = <ReusableMailServer>[];
  for (final account in accounts) {
    final imap = account.imapHost.trim().toLowerCase();
    final smtp = account.smtpHost.trim().toLowerCase();
    if (!isValidMailServerHost(imap) || !isValidMailServerHost(smtp)) {
      continue;
    }
    if (seen.add('$imap|$smtp')) {
      servers.add(ReusableMailServer(
        sourceEmail: account.email.trim(),
        imapHost: imap,
        smtpHost: smtp,
      ));
    }
  }
  return List<ReusableMailServer>.unmodifiable(servers);
}

class MailServerCandidate {
  const MailServerCandidate(this.host);
  final String host;
}

/// Provider presets are only host suggestions. A trusted TLS certificate is
/// required for every connection; no insecure certificate exceptions are used.
/// cPanel domains can require their hosting server name from Connect Devices.
List<MailServerCandidate> cPanelHostCandidates(String email) {
  final domain = email.trim().split('@').last.toLowerCase();
  if (domain.isEmpty || !domain.contains('.')) return const [];

  // Both domains are hosted on the same ParmTech cPanel server.
  // Other customer domains can choose this profile in the account setup UI.
  if (const {'parmtech.au', 'manbirtong.com'}.contains(domain)) {
    return [
      const MailServerCandidate('premium214.web-hosting.com'),
      MailServerCandidate('mail.$domain'),
      MailServerCandidate(domain),
    ];
  }
  if ((domain.startsWith('yahoo.') ||
      const {'ymail.com', 'rocketmail.com'}.contains(domain))) {
    return const [MailServerCandidate('imap.mail.yahoo.com')];
  }
  if (const {'gmail.com', 'googlemail.com'}.contains(domain)) {
    return const [MailServerCandidate('imap.gmail.com')];
  }
  if (domain == 'aol.com') {
    return const [MailServerCandidate('imap.aol.com')];
  }
  if (const {'icloud.com', 'me.com', 'mac.com'}.contains(domain)) {
    return const [MailServerCandidate('imap.mail.me.com')];
  }

  // Prefer mail.domain over the root website hostname, which often has a
  // web-only TLS certificate. If neither host matches its cert, the account
  // must use the provider's explicitly documented secure mail hostname.
  return [
    MailServerCandidate('mail.$domain'),
    MailServerCandidate(domain),
  ];
}

String recommendedSmtpHost(String email) {
  final domain = email.trim().split('@').last.toLowerCase();
  if ((domain.startsWith('yahoo.') ||
      const {'ymail.com', 'rocketmail.com'}.contains(domain))) {
    return 'smtp.mail.yahoo.com';
  }
  if (const {'gmail.com', 'googlemail.com'}.contains(domain)) {
    return 'smtp.gmail.com';
  }
  if (domain == 'aol.com') return 'smtp.aol.com';
  if (const {'icloud.com', 'me.com', 'mac.com'}.contains(domain)) {
    return 'smtp.mail.me.com';
  }
  final candidates = cPanelHostCandidates(email);
  return candidates.isEmpty ? '' : candidates.first.host;
}

String mailSetupHint(String email) {
  final domain = email.trim().split('@').last.toLowerCase();
  if ((domain.startsWith('yahoo.') ||
      const {'ymail.com', 'rocketmail.com', 'aol.com'}.contains(domain))) {
    return 'Yahoo/AOL accounts usually need an App Password from the '
        'provider account-security page.';
  }
  if (const {'gmail.com', 'googlemail.com'}.contains(domain)) {
    return 'Gmail password-only IMAP access requires an eligible App Password. '
        'Regular Google sign-in/OAuth is not implemented in this client.';
  }
  if (const {'icloud.com', 'me.com', 'mac.com'}.contains(domain)) {
    return 'iCloud Mail requires an app-specific password for this mail client.';
  }
  if (const {'outlook.com', 'hotmail.com', 'live.com', 'office365.com'}.contains(domain)) {
    return 'Microsoft mail accounts normally require OAuth sign-in. '
        'This app currently supports password-based IMAP only.';
  }
  return 'For cPanel mail: Email Accounts → Connect Devices → Secure SSL/TLS '
      'Settings. Copy the exact incoming and outgoing server names shown there.';
}

bool isValidMailAddress(String value) {
  final email = value.trim();
  if (email.isEmpty || email.length > 254) return false;

  final at = email.indexOf('@');
  if (at <= 0 || at != email.lastIndexOf('@') || at == email.length - 1) {
    return false;
  }

  final local = email.substring(0, at);
  final domain = email.substring(at + 1);
  if (local.length > 64 ||
      local.startsWith('.') ||
      local.endsWith('.') ||
      local.contains('..') ||
      local.contains(RegExp(r'\s'))) {
    return false;
  }

  final labels = domain.split('.');
  if (labels.length < 2) return false;
  return labels.every(
    (label) =>
        label.isNotEmpty &&
        label.length <= 63 &&
        !label.startsWith('-') &&
        !label.endsWith('-') &&
        RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(label),
  );
}

/// Manual server settings accept a DNS hostname only (not a URL or IP).
/// Implicit TLS is still required on IMAP 993 and SMTP 465.
bool isValidMailServerHost(String value) {
  final host = value.trim();
  if (host.isEmpty || host.length > 253 || host.contains('://') ||
      host.contains('/') || host.contains(':') || host.contains(' ')) {
    return false;
  }
  final labels = host.split('.');
  if (labels.length < 2) return false;
  return labels.every((label) =>
      label.isNotEmpty && label.length <= 63 &&
      !label.startsWith('-') && !label.endsWith('-') &&
      RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(label));
}
