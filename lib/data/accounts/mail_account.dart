class MailAccount {
  static const int imapPort = 993;
  static const int smtpPort = 465;

  const MailAccount({
    required this.email,
    required this.password,
    required this.imapHost,
    required this.smtpHost,
    this.displayName = '',
  });

  final String email;
  final String password;
  final String imapHost;
  final String smtpHost;
  final String displayName;

  String get id => email.trim().toLowerCase();

  Map<String, Object?> toJson() => {
    'email': email,
    'password': password,
    'imapHost': imapHost,
    'smtpHost': smtpHost,
    'displayName': displayName,
  };

  factory MailAccount.fromJson(Map<String, dynamic> json) => MailAccount(
    email: json['email'] as String,
    password: json['password'] as String,
    imapHost: json['imapHost'] as String,
    smtpHost: json['smtpHost'] as String,
    displayName: (json['displayName'] as String?) ?? '',
  );
}

class MailServerCandidate {
  const MailServerCandidate(this.host);
  final String host;
}

/// Uses only server names shown in this account's cPanel settings.
/// Prefer its hosting-server hostname, then try the domain shown by cPanel.
List<MailServerCandidate> cPanelHostCandidates(String email) {
  final domain = email.trim().split('@').last.toLowerCase();
  if (domain.isEmpty || !domain.contains('.')) return const [];

  if (domain == 'parmtech.au') {
    return const [
      MailServerCandidate('premium214.web-hosting.com'),
      MailServerCandidate('parmtech.au'),
    ];
  }
  // Ordinary cPanel setups may use either the root domain or mail.domain.
  // We never skip TLS certificate validation for either candidate.
  return [MailServerCandidate(domain), MailServerCandidate('mail.$domain')];
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
