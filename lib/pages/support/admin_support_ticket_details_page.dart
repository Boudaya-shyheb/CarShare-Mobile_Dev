import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/support_ticket.dart';
import '../../models/support_ticket_detail.dart';
import '../../services/support_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/support_status_badge.dart';

class AdminSupportTicketDetailsPage extends StatefulWidget {
  const AdminSupportTicketDetailsPage({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<AdminSupportTicketDetailsPage> createState() =>
      _AdminSupportTicketDetailsPageState();
}

class _AdminSupportTicketDetailsPageState
    extends State<AdminSupportTicketDetailsPage> {
  late Future<AdminSupportTicketDetails> _details = _load();
  bool _working = false;

  Future<AdminSupportTicketDetails> _load() =>
      SupportService.instance.adminTicketDetails(widget.ticketId);

  void _refresh() {
    final details = _load();
    setState(() {
      _details = details;
    });
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    setState(() => _working = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changeStatus(String status, String title) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _SupportReasonDialog(title: title),
    );
    if (reason == null) return;
    await _run(
      () => SupportService.instance.changeAdminStatus(
        ticketId: widget.ticketId,
        status: status,
        reason: reason,
      ),
      'Ticket status updated.',
    );
  }

  Future<void> _recordDecision() async {
    final decision = await showDialog<_DecisionInput>(
      context: context,
      builder: (_) => const _DecisionDialog(),
    );
    if (decision == null) return;
    await _run(
      () => SupportService.instance.createAdminDecision(
        ticketId: widget.ticketId,
        result: decision.result,
        reason: decision.reason,
        penaltyPoints: decision.penaltyPoints,
      ),
      'Support decision recorded.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      title: const Text('Support case'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _working ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<AdminSupportTicketDetails>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton(
              onPressed: _refresh,
              child: Text('Try again: ${snapshot.error}'),
            ),
          );
        }
        return _body(snapshot.data!);
      },
    ),
  );

  Widget _body(AdminSupportTicketDetails details) {
    final ticket = details.ticket;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.reference,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SupportStatusBadge(status: ticket.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${details.openedByName} · ${details.openedByEmail}',
                style: const TextStyle(color: carShareMuted),
              ),
              const SizedBox(height: 14),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.category,
                      style: const TextStyle(
                        color: supportDarkGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ticket.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(ticket.description),
                    const SizedBox(height: 10),
                    Text(
                      'Priority: ${details.priorityScore ?? 0} · Created ${ticket.createdLabel}',
                      style: const TextStyle(
                        color: carShareMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (details.tripId != null)
                      Text(
                        'Trip: ${ticket.trip}${details.reservationId == null ? '' : '\nReservation reference: ${details.reservationId}'}',
                        style: const TextStyle(
                          color: carShareMuted,
                          fontSize: 12,
                        ),
                      ),
                    if (ticket.reportedUserName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Person concerned: ${ticket.reportedUserName} · ${ticket.reportedUserRoleLabel}',
                        style: const TextStyle(
                          color: supportDarkGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (details.reportedUserId != null)
                      Text(
                        'Reported user: ${details.reportedUserId}',
                        style: const TextStyle(
                          color: carShareMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _actionButtons(ticket.status),
              const SizedBox(height: 20),
              _SectionTitle('Evidence', details.evidence.length),
              if (details.evidence.isEmpty)
                const _EmptyLine('No evidence was submitted.'),
              ...details.evidence.map(
                (item) => Card(
                  child: ListTile(
                    leading: item.contentType.startsWith('image/')
                        ? _AdminEvidenceThumbnail(
                            ticketId: ticket.id,
                            evidence: item,
                          )
                        : const Icon(Icons.description_outlined),
                    title: Text(item.fileName),
                    subtitle: Text(
                      '${item.type} · ${_fileSize(item.fileSize)}\n'
                      'Added by ${item.uploadedByName ?? 'Unknown user'}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle('Statements', details.statements.length),
              if (details.statements.isEmpty)
                const _EmptyLine('No statement was submitted.'),
              ...details.statements.map(
                (item) => _Panel(
                  margin: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(item.text),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle('Status history', details.history.length),
              ...details.history.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: supportGreen,
                  ),
                  title: Text(item.toStatus.replaceAll('_', ' ')),
                  subtitle: Text(
                    '${item.reason ?? 'Status updated'} · ${_date(item.createdAt)}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SectionTitle('Decisions', details.decisions.length),
              if (details.decisions.isEmpty)
                const _EmptyLine('No decision has been recorded.'),
              ...details.decisions.map(
                (item) => _Panel(
                  margin: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Decision ${item.decisionNumber}: ${item.result}\n'
                    '${item.reason}\nPenalty points: ${item.penaltyPoints}'
                    '${item.finalDecision ? ' · Final' : ''}',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle('Contestations', details.contestations.length),
              if (details.contestations.isEmpty)
                const _EmptyLine('No contestation was submitted.'),
              ...details.contestations.map(
                (item) => _Panel(
                  margin: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${item.userName} · ${_date(item.createdAt)}\n${item.reason}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButtons(TicketStatus status) {
    final buttons = <Widget>[];
    if (status == TicketStatus.open) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: _working
              ? null
              : () => _changeStatus('AWAITING_RESPONSE', 'Request a response'),
          icon: const Icon(Icons.question_answer_outlined),
          label: const Text('Request response'),
        ),
      );
    }
    if (status == TicketStatus.open ||
        status == TicketStatus.awaitingResponse ||
        status == TicketStatus.contested) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: _working
              ? null
              : () => _changeStatus('UNDER_REVIEW', 'Start review'),
          icon: const Icon(Icons.manage_search_outlined),
          label: const Text('Start review'),
        ),
      );
    }
    if (status == TicketStatus.open ||
        status == TicketStatus.awaitingResponse ||
        status == TicketStatus.underReview ||
        status == TicketStatus.contested) {
      buttons.add(
        FilledButton.icon(
          onPressed: _working ? null : _recordDecision,
          icon: const Icon(Icons.gavel_outlined),
          label: const Text('Record decision'),
        ),
      );
    }
    if (status == TicketStatus.resolved) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: _working
              ? null
              : () => _changeStatus('CLOSED', 'Close ticket'),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Close ticket'),
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  static String _date(DateTime? value) {
    if (value == null) return 'Recently';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  static String _fileSize(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _AdminEvidenceThumbnail extends StatefulWidget {
  const _AdminEvidenceThumbnail({
    required this.ticketId,
    required this.evidence,
  });

  final String ticketId;
  final TicketEvidenceItem evidence;

  @override
  State<_AdminEvidenceThumbnail> createState() =>
      _AdminEvidenceThumbnailState();
}

class _AdminEvidenceThumbnailState extends State<_AdminEvidenceThumbnail> {
  late final Future<Uint8List> _bytes = SupportService.instance
      .adminEvidenceBytes(widget.ticketId, widget.evidence.id);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.image_outlined, color: supportGreen),
        );
      }
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            child: InteractiveViewer(child: Image.memory(snapshot.data!)),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            snapshot.data!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
          ),
        ),
      );
    },
  );
}

class _SupportReasonDialog extends StatefulWidget {
  const _SupportReasonDialog({required this.title});
  final String title;

  @override
  State<_SupportReasonDialog> createState() => _SupportReasonDialogState();
}

class _SupportReasonDialogState extends State<_SupportReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: CarShareTextField(
        controller: _reason,
        label: 'Reason',
        icon: Icons.notes_outlined,
        minLines: 3,
        maxLines: 5,
        validator: (value) => value == null || value.trim().isEmpty
            ? 'A reason is required.'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(context, _reason.text.trim());
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class _DecisionDialog extends StatefulWidget {
  const _DecisionDialog();

  @override
  State<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends State<_DecisionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _points = TextEditingController(text: '0');
  String _result = 'CONFIRMED';

  @override
  void dispose() {
    _reason.dispose();
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record support decision'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _result,
              decoration: const InputDecoration(labelText: 'Result'),
              items: const [
                DropdownMenuItem(value: 'CONFIRMED', child: Text('Confirmed')),
                DropdownMenuItem(value: 'PARTIAL', child: Text('Partial')),
                DropdownMenuItem(value: 'REJECTED', child: Text('Rejected')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _result = value;
                  if (value == 'REJECTED') _points.text = '0';
                });
              },
            ),
            const SizedBox(height: 12),
            CarShareTextField(
              controller: _points,
              label: 'Penalty points (0 to 12)',
              icon: Icons.warning_amber_outlined,
              keyboardType: TextInputType.number,
              validator: (value) {
                final points = int.tryParse(value ?? '');
                if (points == null || points < 0 || points > 12) {
                  return 'Enter a number from 0 to 12.';
                }
                if (_result == 'REJECTED' && points != 0) {
                  return 'A rejected complaint has 0 points.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            CarShareTextField(
              controller: _reason,
              label: 'Decision reason',
              icon: Icons.notes_outlined,
              minLines: 3,
              maxLines: 5,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'A decision reason is required.'
                  : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _DecisionInput(
              result: _result,
              reason: _reason.text.trim(),
              penaltyPoints: int.parse(_points.text),
            ),
          );
        },
        child: const Text('Save decision'),
      ),
    ],
  );
}

class _DecisionInput {
  const _DecisionInput({
    required this.result,
    required this.reason,
    required this.penaltyPoints,
  });

  final String result;
  final String reason;
  final int penaltyPoints;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Text(
    '$label ($count)',
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
  );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: const TextStyle(color: carShareMuted)),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.margin});
  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: margin,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: carShareBorder),
    ),
    child: child,
  );
}
