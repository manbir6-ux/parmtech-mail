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

/// Starts with the mailbox domain, then checks the verified server fallback
/// supplied by the owner. A production build should resolve provider settings
/// before adding any account-specific fallback host here.
List<MailServerCandidate> cPanelHostCandidates(String email) {
  final domain = email.trim().split('@').last.toLowerCase();
  if (domain.isEmpty || !domain.contains('.')) return const [];

  final hosts = <String>[domain];
  if (domain == 'parmtech.au') {
    hosts.add('premium214.web-hosting.com');
  }
  hosts.add('mail.$domain');
  return hosts.toSet().map(MailServerCandidate.new).toList(growable: false);
}
