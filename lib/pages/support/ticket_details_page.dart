import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/support_ticket.dart';
import '../../models/support_ticket_detail.dart';
import '../../services/auth_service.dart';
import '../../services/support_service.dart';
import '../../theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/round_back_button.dart';
import '../../widgets/status_chip.dart';
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
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: roundBackAppBar(
      context,
      title: 'Support ticket',
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load this ticket',
                  line: authErrorMessage(snapshot.error!),
                ),
                OutlinedButton(
                  onPressed: _refresh,
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        return _body(snapshot.data!);
      },
    ),
  );

  Widget _body(SupportTicketDetails details) {
    final currentUserId = AuthService.instance.currentUser.value?.id;
    final mine = ticket.userId == currentUserId;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // The ticket itself.
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AdminPill(ticket.reference, colour: carShareMuted),
                        AdminPill(
                          humanize(ticket.category),
                          colour: supportDarkGreen,
                        ),
                        if (ticket.deadline != null)
                          _DeadlineBadge(deadline: ticket.deadline!),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ticket.title,
                      style: const TextStyle(
                        color: carShareText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ticket.description,
                      style: const TextStyle(
                        color: carShareText,
                        height: 1.45,
                        fontSize: 15,
                      ),
                    ),
                    const Divider(height: 28),
                    AdminInfoLine(
                      Icons.schedule,
                      'Opened ${ticket.createdLabel}',
                      maxLines: 1,
                    ),
                    if (ticket.trip != 'General request')
                      AdminInfoLine(
                        Icons.route_outlined,
                        '${ticket.trip} (trip data, read only)',
                      ),
                    if (ticket.reportedUserName != null)
                      AdminInfoLine(
                        Icons.person_search_outlined,
                        'Person concerned: ${ticket.reportedUserName} · ${ticket.reportedUserRoleLabel}',
                        colour: supportDarkGreen,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Notice(
                icon: mine
                    ? Icons.outgoing_mail
                    : Icons.record_voice_over_outlined,
                text: mine
                    ? 'You opened this ticket. The other participant can respond with a statement and evidence.'
                    : 'You are involved in this ticket. Add your statement and evidence before review starts.',
              ),
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Progress',
                icon: Icons.timeline_rounded,
                trailing: Text(
                  '${details.history.length} ${details.history.length == 1 ? 'update' : 'updates'}',
                  style: const TextStyle(color: carShareMuted, fontSize: 13),
                ),
                child: _StatusTimeline(
                  status: ticket.status,
                  historyCount: details.history.length,
                ),
              ),
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Status history',
                icon: Icons.history_rounded,
                child: Column(
                  children: [
                    for (var i = 0; i < details.history.length; i++)
                      _historyRow(
                        details.history[i],
                        i == details.history.length - 1,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Evidence (${details.evidence.length})',
                icon: Icons.attach_file_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (details.evidence.isEmpty)
                      const Text(
                        'No evidence yet.',
                        style: TextStyle(color: carShareMuted),
                      ),
                    for (var i = 0; i < details.evidence.length; i++) ...[
                      if (i > 0) const Divider(height: 22),
                      _evidenceRow(details.evidence[i], currentUserId),
                    ],
                    if (_canContribute) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              onPressed: _working ? null : _addPhoto,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: const Text('Add photo'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              onPressed: _working ? null : _addDocument,
                              icon: const Icon(Icons.attach_file_rounded),
                              label: const Text('Add PDF'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Statements (${details.statements.length})',
                icon: Icons.chat_bubble_outline_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (details.statements.isEmpty)
                      const Text(
                        'No statements yet.',
                        style: TextStyle(color: carShareMuted),
                      ),
                    for (var i = 0; i < details.statements.length; i++) ...[
                      if (i > 0) const Divider(height: 22),
                      Text(
                        details.statements[i].authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: carShareText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        details.statements[i].text,
                        style: const TextStyle(height: 1.4),
                      ),
                    ],
                    if (_canContribute &&
                        !details.statements.any(
                          (item) => item.authorId == currentUserId,
                        )) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: _working ? null : _addStatement,
                          icon: const Icon(Icons.add_comment_outlined),
                          label: const Text('Add your response'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Decisions (${details.decisions.length})',
                icon: Icons.gavel_outlined,
                child: details.decisions.isEmpty
                    ? const Text(
                        'No decision yet.',
                        style: TextStyle(color: carShareMuted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var i = 0;
                            i < details.decisions.length;
                            i++
                          ) ...[
                            if (i > 0) const Divider(height: 22),
                            _decisionRow(details.decisions[i]),
                          ],
                        ],
                      ),
              ),
              if (ticket.status == TicketStatus.resolved &&
                  details.decisions.isNotEmpty &&
                  !details.decisions.last.finalDecision) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    foregroundColor: carShareDanger,
                    side: const BorderSide(
                      color: carShareDangerTint,
                      width: 1.5,
                    ),
                  ),
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

  Widget _historyRow(dynamic item, bool last) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(Icons.circle, size: 10, color: supportGreen),
            ),
            if (!last)
              Expanded(child: Container(width: 2, color: carShareTint)),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  humanize(item.toStatus),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: carShareText,
                  ),
                ),
                Text(
                  '${item.reason ?? 'Status updated'}',
                  style: const TextStyle(color: carShareMuted, fontSize: 13),
                ),
                Text(
                  _date(item.createdAt),
                  style: const TextStyle(color: carShareMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _evidenceRow(TicketEvidenceItem item, String? currentUserId) => Row(
    children: [
      item.contentType.startsWith('image/')
          ? _EvidenceThumbnail(ticketId: ticket.id, evidence: item)
          : const AdminIconBadge(Icons.description_outlined, size: 48),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: carShareText,
              ),
            ),
            Text(
              '${humanize(item.type)} · ${_fileSize(item.fileSize)}',
              style: const TextStyle(color: carShareMuted, fontSize: 13),
            ),
            Text(
              'Added by ${item.uploadedByName ?? 'Unknown user'}',
              style: const TextStyle(color: carShareMuted, fontSize: 13),
            ),
          ],
        ),
      ),
      if (_canContribute && item.uploadedByUserId == currentUserId)
        IconButton(
          tooltip: 'Delete evidence',
          onPressed: _working ? null : () => _deleteEvidence(item.id),
          icon: const Icon(Icons.delete_outline),
          color: carShareDanger,
        ),
    ],
  );

  Widget _decisionRow(dynamic item) {
    final result = '${item.result}'.toUpperCase();
    final colour = result == 'REJECTED'
        ? carShareMuted
        : result == 'PARTIAL'
        ? carShareWarning
        : carShareGreen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Decision ${item.decisionNumber}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: carShareText,
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(label: humanize(item.result), colour: colour),
            if (item.finalDecision) ...[
              const SizedBox(width: 6),
              const AdminPill('Final', colour: carShareMuted),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text('${item.reason}', style: const TextStyle(height: 1.4)),
        AdminInfoLine(
          Icons.warning_amber_outlined,
          'Penalty: ${item.penaltyPoints} ${item.penaltyPoints == 1 ? 'point' : 'points'}',
          maxLines: 1,
        ),
      ],
    );
  }

  String _date(DateTime? value) => adminDateTime(value, fallback: 'Recently');

  String _fileSize(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status, required this.historyCount});

  final TicketStatus status;
  final int historyCount;

  @override
  Widget build(BuildContext context) {
    const steps = ['Open', 'Awaiting reply', 'Under review', 'Resolved'];
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
        if (status == TicketStatus.withdrawn)
          const Text(
            'This ticket was withdrawn.',
            style: TextStyle(color: carShareMuted),
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
                              height: 3,
                              color: index <= currentStep
                                  ? supportGreen
                                  : carShareBorder,
                            ),
                          ),
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: reached
                              ? supportGreen
                              : carShareBorder,
                          child: reached
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : null,
                        ),
                        if (index < steps.length - 1)
                          Expanded(
                            child: Container(
                              height: 3,
                              color: index < currentStep
                                  ? supportGreen
                                  : carShareBorder,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      steps[index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: reached ? supportDarkGreen : carShareMuted,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: reached ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        if (status == TicketStatus.contested) ...[
          const SizedBox(height: 12),
          const AdminPill(
            'Decision contested · under a second review',
            colour: supportWarningText,
            icon: Icons.gavel_outlined,
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
  Widget build(BuildContext context) => AdminPill(
    'Reply by ${adminDate(deadline)}',
    colour: supportWarningText,
    icon: Icons.timer_outlined,
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

/// A soft tinted note: who may do what on this ticket.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: carShareTint.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: supportDarkGreen, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: supportDarkGreen,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
