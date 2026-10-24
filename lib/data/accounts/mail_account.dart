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

  // Legacy account records may carry old hostname guesses. Never reuse
  // those endpoints: all active sessions must use the private mail server.
  Map<String, Object?> toJson() => {
    'email': email,
    'password': password,
    'imapHost': parmTechMailServerHost,
    'smtpHost': parmTechMailServerHost,
    'displayName': displayName,
    'useCustomServer': false,
  };

  factory MailAccount.fromJson(Map<String, dynamic> json) => MailAccount(
    email: json['email'] as String,
    password: json['password'] as String,
    imapHost: parmTechMailServerHost,
    smtpHost: parmTechMailServerHost,
    displayName: (json['displayName'] as String?) ?? '',
    useCustomServer: false,
  );
}

/// Reuses the TLS hostnames of an account already verified on this device.
/// An explicit user choice is required before applying these to another
/// mailbox, since unrelated email domains may use different providers.
/// One privately managed mail server for every ParmTech Mail account.
/// Authentication is attempted only against this host, regardless of domain.
const String parmTechMailServerHost = 'premium214.web-hosting.com';

class MailServerCandidate {
  const MailServerCandidate(this.host);
  final String host;
}

/// Single private hosting profile. No guessed mail.domain.com addresses and
/// no public provider IMAP/SMTP settings (Gmail, Yahoo, etc).
List<MailServerCandidate> cPanelHostCandidates(String email) =>
    isValidMailAddress(email)
        ? const [MailServerCandidate(parmTechMailServerHost)]
        : const [];

String recommendedSmtpHost(String email) =>
    isValidMailAddress(email) ? parmTechMailServerHost : '';

String mailSetupHint(String email) =>
    'Private ParmTech mail hosting only. Only mailboxes created on this '
    'server can sign in. Secure IMAP 993 and SMTP 465 are configured '
    'automatically.';

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
