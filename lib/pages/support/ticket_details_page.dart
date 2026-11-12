import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/support_ticket.dart';
import '../../models/support_ticket_detail.dart';
import '../../services/auth_service.dart';
import '../../services/support_service.dart';
import '../../theme.dart';
import '../../widgets/support_status_badge.dart';
import '../../widgets/support_evidence_section.dart';

class TicketDetailsPage extends StatefulWidget {
  const TicketDetailsPage({super.key, required this.ticket});

  final SupportTicket ticket;

  @override
  State<TicketDetailsPage> createState() => _TicketDetailsPageState();
}

class _TicketDetailsPageState extends State<TicketDetailsPage> {
  late Future<SupportTicketDetails> _details = _load();
  bool _working = false;

  SupportTicket get ticket => widget.ticket;
  bool get _canContribute =>
      ticket.status == TicketStatus.open ||
      ticket.status == TicketStatus.awaitingResponse;

  Future<SupportTicketDetails> _load() =>
      SupportService.instance.ticketDetails(ticket.id);

  void _refresh() {
    final details = _load();
    setState(() {
      _details = details;
    });
  }

  Future<String?> _askText(String title, String label) => showDialog<String>(
    context: context,
    builder: (_) => _SupportTextDialog(title: title, label: label),
  );

  Future<void> _addStatement() async {
    final text = await _askText('Add a statement', 'Your statement');
    if (text == null) return;
    await _run(() => SupportService.instance.addStatement(ticket.id, text));
  }

  Future<void> _contest() async {
    final reason = await _askText('Contest decision', 'Reason');
    if (reason == null) return;
    await _run(() => SupportService.instance.contest(ticket.id, reason));
  }

  Future<void> _addPhoto() async {
    final photo = await pickSupportPhoto(context);
    if (photo == null) return;
    final bytes = photo.bytes;
    if (bytes == null) return;
    final extension = photo.name.split('.').last.toLowerCase();
    final mimeType = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    await _run(
      () => SupportService.instance.uploadEvidence(
        ticketId: ticket.id,
        bytes: bytes,
        fileName: photo.name,
        mimeType: mimeType,
        type: 'PHOTO',
      ),
    );
  }

  Future<void> _addDocument() async {
    final document = await pickSupportDocument(context);
    if (document == null || document.bytes == null) return;
    await _run(
      () => SupportService.instance.uploadEvidence(
        ticketId: ticket.id,
        bytes: document.bytes!,
        fileName: document.name,
        mimeType: 'application/pdf',
        type: 'DOCUMENT',
      ),
    );
  }

  Future<void> _deleteEvidence(String evidenceId) =>
      _run(() => SupportService.instance.deleteEvidence(ticket.id, evidenceId));

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: carShareBackground,
      surfaceTintColor: carShareBackground,
      title: Text(
        ticket.reference,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: carShareText,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(child: SupportStatusBadge(status: ticket.status)),
        ),
      ],
    ),
    body: FutureBuilder<SupportTicketDetails>(
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

  Widget _body(SupportTicketDetails details) {
    final currentUserId = AuthService.instance.currentUser.value?.id;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${ticket.trip} · ${ticket.createdLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: carShareMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (ticket.deadline != null)
                    _DeadlineBadge(deadline: ticket.deadline!),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ticket.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: carShareText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ticket.category,
                style: const TextStyle(
                  color: supportDarkGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (ticket.trip != 'General request') ...[
                _Panel(
                  child: Row(
                    children: [
                      const Icon(Icons.route_outlined, color: supportDarkGreen),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Trip data · read only',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              ticket.trip,
                              style: const TextStyle(
                                color: carShareMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (ticket.reportedUserName != null) ...[
                _Panel(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_search_outlined,
                        color: supportDarkGreen,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Person concerned',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${ticket.reportedUserName} · ${ticket.reportedUserRoleLabel}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              'This ticket was filed against this person.',
                              style: TextStyle(
                                color: carShareMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _Panel(
                child: Row(
                  children: [
                    Icon(
                      ticket.userId == currentUserId
                          ? Icons.outgoing_mail
                          : Icons.record_voice_over_outlined,
                      color: supportDarkGreen,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ticket.userId == currentUserId
                            ? 'You opened this ticket. The other participant can respond with a statement and evidence.'
                            : 'You are involved in this ticket. Add your statement and evidence before review starts.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Panel(
                child: _StatusTimeline(
                  status: ticket.status,
                  historyCount: details.history.length,
                ),
              ),
              const SizedBox(height: 14),
              _Panel(child: Text(ticket.description)),
              const SizedBox(height: 18),
              _SectionTitle('Status history'),
              ...details.history.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: supportGreen,
                  ),
                  title: Text(
                    item.toStatus.replaceAll('_', ' '),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${item.reason ?? 'Status updated'} · ${_date(item.createdAt)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SectionTitle(
                      'Evidence (${details.evidence.length})',
                    ),
                  ),
                  if (_canContribute)
                    TextButton.icon(
                      onPressed: _working ? null : _addPhoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add photo'),
                    ),
                  if (_canContribute)
                    TextButton.icon(
                      onPressed: _working ? null : _addDocument,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: const Text('Add PDF'),
                    ),
                ],
              ),
              if (details.evidence.isEmpty)
                const Text(
                  'No evidence.',
                  style: TextStyle(color: carShareMuted),
                ),
              ...details.evidence.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: item.contentType.startsWith('image/')
                      ? _EvidenceThumbnail(ticketId: ticket.id, evidence: item)
                      : const Icon(
                          Icons.description_outlined,
                          color: supportGreen,
                        ),
                  title: Text(item.fileName),
                  subtitle: Text(
                    '${item.type} · ${_fileSize(item.fileSize)}\n'
                    'Added by ${item.uploadedByName ?? 'Unknown user'}',
                  ),
                  isThreeLine: true,
                  trailing:
                      _canContribute && item.uploadedByUserId == currentUserId
                      ? IconButton(
                          onPressed: _working
                              ? null
                              : () => _deleteEvidence(item.id),
                          icon: const Icon(Icons.delete_outline),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SectionTitle(
                      'Statements (${details.statements.length})',
                    ),
                  ),
                  if (_canContribute &&
                      !details.statements.any(
                        (item) => item.authorId == currentUserId,
                      ))
                    TextButton.icon(
                      onPressed: _working ? null : _addStatement,
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('Respond'),
                    ),
                ],
              ),
              if (details.statements.isEmpty)
                const Text(
                  'No statements.',
                  style: TextStyle(color: carShareMuted),
                ),
              ...details.statements.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.authorName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(item.text),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle('Decisions (${details.decisions.length})'),
              if (details.decisions.isEmpty)
                const Text(
                  'No decision yet.',
                  style: TextStyle(color: carShareMuted),
                ),
              ...details.decisions.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Decision ${item.decisionNumber}: ${item.result}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(item.reason),
                        Text(
                          'Penalty points: ${item.penaltyPoints}${item.finalDecision ? ' · Final' : ''}',
                          style: const TextStyle(color: carShareMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (ticket.status == TicketStatus.resolved &&
                  details.decisions.isNotEmpty &&
                  !details.decisions.last.finalDecision) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: _working ? null : _contest,
                  icon: const Icon(Icons.gavel_outlined),
                  label: const Text('Contest this decision'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return 'Recently';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String _fileSize(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: carShareText,
      fontSize: 14,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status, required this.historyCount});

  final TicketStatus status;
  final int historyCount;

  @override
  Widget build(BuildContext context) {
    const steps = ['Open', 'Awaiting\nreply', 'Under\nreview', 'Resolved'];
    final currentStep = switch (status) {
      TicketStatus.open => 0,
      TicketStatus.awaitingResponse => 1,
      TicketStatus.underReview || TicketStatus.contested => 2,
      TicketStatus.resolved || TicketStatus.closed => 3,
      TicketStatus.withdrawn => -1,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ticket progress',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            Text(
              '$historyCount updates',
              style: const TextStyle(color: carShareMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (status == TicketStatus.withdrawn)
          const Text(
            'This ticket was withdrawn.',
            style: TextStyle(color: carShareMuted, fontSize: 12),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length, (index) {
              final reached = index <= currentStep;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (index > 0)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: index <= currentStep
                                  ? supportGreen
                                  : carShareBorder,
                            ),
                          ),
                        CircleAvatar(
                          radius: 8,
                          backgroundColor: reached
                              ? supportGreen
                              : carShareBorder,
                          child: reached
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 10,
                                )
                              : null,
                        ),
                        if (index < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: index < currentStep
                                  ? supportGreen
                                  : carShareBorder,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      steps[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: reached ? supportDarkGreen : carShareMuted,
                        fontSize: 9,
                        height: 1.15,
                        fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        if (status == TicketStatus.contested) ...[
          const SizedBox(height: 8),
          const Text(
            'Decision contested · under a second review',
            style: TextStyle(
              color: supportWarningText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _DeadlineBadge extends StatelessWidget {
  const _DeadlineBadge({required this.deadline});

  final DateTime deadline;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: supportWarningBackground,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      'Due ${deadline.month}/${deadline.day}',
      style: const TextStyle(
        color: supportWarningText,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EvidenceThumbnail extends StatefulWidget {
  const _EvidenceThumbnail({required this.ticketId, required this.evidence});

  final String ticketId;
  final TicketEvidenceItem evidence;

  @override
  State<_EvidenceThumbnail> createState() => _EvidenceThumbnailState();
}

class _EvidenceThumbnailState extends State<_EvidenceThumbnail> {
  late final Future<Uint8List> _bytes = SupportService.instance.evidenceBytes(
    widget.ticketId,
    widget.evidence.id,
  );

  Future<void> _showPhoto(Uint8List bytes) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return InkWell(
          onTap: () => _showPhoto(snapshot.data!),
          borderRadius: BorderRadius.circular(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              snapshot.data!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _EvidencePlaceholder(),
            ),
          ),
        );
      }
      if (snapshot.hasError) return const _EvidencePlaceholder();
      return const SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: EdgeInsets.all(13),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    },
  );
}

class _EvidencePlaceholder extends StatelessWidget {
  const _EvidencePlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: carShareTint,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.broken_image_outlined, color: supportDarkGreen),
  );
}

class _SupportTextDialog extends StatefulWidget {
  const _SupportTextDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_SupportTextDialog> createState() => _SupportTextDialogState();
}

class _SupportTextDialogState extends State<_SupportTextDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      minLines: 3,
      maxLines: 6,
      decoration: InputDecoration(labelText: widget.label),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final text = _controller.text.trim();
          if (text.isNotEmpty) Navigator.pop(context, text);
        },
        child: const Text('Send'),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: carShareBorder),
    ),
    child: child,
  );
}
