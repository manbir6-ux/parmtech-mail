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

/// Uses only the two server names verified for this Namecheap cPanel account:
/// the SSL/TLS hostname shown in cPanel and the hosting server hostname from
/// the cPanel URL. Do not synthesize `mail.<domain>` for parmtech.au.
List<MailServerCandidate> cPanelHostCandidates(String email) {
  final domain = email.trim().split('@').last.toLowerCase();
  if (domain.isEmpty || !domain.contains('.')) return const [];

  if (domain == 'parmtech.au') {
    return const [
      MailServerCandidate('parmtech.au'),
      MailServerCandidate('premium214.web-hosting.com'),
    ];
  }
  return [MailServerCandidate(domain)];
}
