import 'package:flutter/material.dart';

import '../data/accounts/mail_account.dart';
import '../data/mail/cpanel_mail_service.dart';

class InlineReplyBox extends StatefulWidget {
  const InlineReplyBox({
    super.key,
    required this.account,
    required this.mailService,
    required this.message,
    this.onSent,
  });
  final MailAccount account;
  final CpanelMailService mailService;
  final MailItem message;
  final Future<void> Function()? onSent;

  @override
  State<InlineReplyBox> createState() => _InlineReplyBoxState();
}

class _InlineReplyBoxState extends State<InlineReplyBox> {
  final _reply = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    final recipient = widget.message.replyToAddress.isNotEmpty
        ? widget.message.replyToAddress
        : widget.message.senderAddress;
    if (text.isEmpty || _sending || !isValidMailAddress(recipient)) return;
    setState(() => _sending = true);
    try {
      final subject = widget.message.subject;
      await widget.mailService.send(
        widget.account,
        to: recipient,
        subject: subject.toLowerCase().startsWith('re:') ? subject : 'Re: $subject',
        body: text,
        inReplyTo: widget.message.messageId,
        references: widget.message.references,
      );
      if (!mounted) return;
      _reply.clear();
      setState(() => _sent = true);
      await widget.onSent?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reply not sent: ${friendlyMailError(error)}'),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quick reply',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reply,
            enabled: !_sending,
            minLines: 2,
            maxLines: 8,
            onChanged: (_) {
              if (_sent) setState(() => _sent = false);
            },
            decoration: InputDecoration(
              hintText: 'Write a reply…',
              filled: true,
              fillColor: color.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_sent) ...[
                Icon(Icons.check_circle_outline, color: color.primary, size: 17),
                const SizedBox(width: 6),
                const Expanded(child: Text('Reply sent')),
              ] else
                const Spacer(),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send reply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
