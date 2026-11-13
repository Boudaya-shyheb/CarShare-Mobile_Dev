import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/support_ticket.dart';
import '../../models/support_ticket_detail.dart';
import '../../services/support_service.dart';
import '../../services/geo_service.dart';
import '../../theme.dart';
import '../../widgets/admin_ui.dart';
import '../../widgets/form_field.dart';
import '../../widgets/round_back_button.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/support_status_badge.dart';
import '../../services/auth_service.dart' show authErrorMessage;

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
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Runs the analysis, then shows what it really found: complete, or partial with the reason
  /// (Tika unreachable, for example), plus the hash and an excerpt of the extracted text.
  Future<void> _analyze(TicketEvidenceItem evidence) async {
    setState(() => _working = true);
    try {
      final result = await SupportService.instance.analyzeEvidence(
        widget.ticketId,
        evidence.id,
      );
      if (!mounted) return;
      _refresh();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            _AnalysisSheet(fileName: evidence.fileName, result: result),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
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
    appBar: roundBackAppBar(
      context,
      title: 'Support case',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _working ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 12),
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
    final analysis = details.advanced?.analysis;
    final sla = analysis == null ? null : _slaFromAnalysis(analysis);
    final priority = priorityState(
      analysis?.score ?? details.priorityScore ?? 0,
    );
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 1. The case itself: who, what, how urgent.
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ticket.reference,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: carShareText,
                            ),
                          ),
                        ),
                        SupportStatusBadge(status: ticket.status),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AdminPill(
                          '${priority.label} · ${analysis?.score ?? details.priorityScore ?? 0}',
                          colour: priority.colour,
                          icon: Icons.flag_outlined,
                        ),
                        if (sla != null)
                          AdminPill(
                            sla.label,
                            colour: sla.colour,
                            icon: Icons.timer_outlined,
                          ),
                        AdminPill(
                          humanize(ticket.category),
                          colour: supportDarkGreen,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      ticket.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: carShareText,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ticket.description,
                      style: const TextStyle(color: carShareText, height: 1.45),
                    ),
                    const Divider(height: 28),
                    AdminInfoLine(
                      Icons.person_outline,
                      '${details.openedByName} · ${details.openedByEmail}',
                      maxLines: 2,
                    ),
                    AdminInfoLine(
                      Icons.schedule,
                      'Created ${ticket.createdLabel}',
                      maxLines: 1,
                    ),
                    if (details.tripId != null)
                      AdminInfoLine(
                        Icons.route_outlined,
                        'Trip: ${ticket.trip}',
                      ),
                    if (ticket.reportedUserName != null)
                      AdminInfoLine(
                        Icons.report_outlined,
                        'Person concerned: ${ticket.reportedUserName} · ${ticket.reportedUserRoleLabel}',
                        colour: supportDarkGreen,
                      ),
                    if (details.reservationId != null ||
                        details.reportedUserId != null)
                      AdminCollapsible(
                        title: 'Show details',
                        children: [
                          if (details.reservationId != null)
                            AdminFact(
                              'Reservation',
                              '${details.reservationId}',
                            ),
                          if (details.reportedUserId != null)
                            AdminFact(
                              'Reported user id',
                              '${details.reportedUserId}',
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // 2. What the admin can do now.
              _actionButtons(ticket.status),
              const SizedBox(height: 18),
              // 3. The advanced engine: priority, SLA, risk, analysis.
              _advancedPanel(details),
              const SizedBox(height: 18),
              // 4. The file.
              AdminBlock(
                title: 'Evidence (${details.evidence.length})',
                icon: Icons.attach_file_rounded,
                child: details.evidence.isEmpty
                    ? const Text(
                        'No evidence was submitted.',
                        style: TextStyle(color: carShareMuted),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < details.evidence.length; i++) ...[
                            if (i > 0) const Divider(height: 22),
                            _evidenceRow(ticket.id, details.evidence[i]),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Statements (${details.statements.length})',
                icon: Icons.chat_bubble_outline_rounded,
                child: details.statements.isEmpty
                    ? const Text(
                        'No statement was submitted.',
                        style: TextStyle(color: carShareMuted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var i = 0;
                            i < details.statements.length;
                            i++
                          ) ...[
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
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Status history (${details.history.length})',
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
                title: 'Decisions (${details.decisions.length})',
                icon: Icons.gavel_outlined,
                child: details.decisions.isEmpty
                    ? const Text(
                        'No decision has been recorded.',
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
              const SizedBox(height: 18),
              AdminBlock(
                title: 'Contestations (${details.contestations.length})',
                icon: Icons.record_voice_over_outlined,
                child: details.contestations.isEmpty
                    ? const Text(
                        'No contestation was submitted.',
                        style: TextStyle(color: carShareMuted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var i = 0;
                            i < details.contestations.length;
                            i++
                          ) ...[
                            if (i > 0) const Divider(height: 22),
                            Text(
                              '${details.contestations[i].userName} · ${_date(details.contestations[i].createdAt)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: carShareText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              details.contestations[i].reason,
                              style: const TextStyle(height: 1.4),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// SLA label and colour from the engine's own numbers (remaining minutes, state).
  ({String label, Color colour}) _slaFromAnalysis(dynamic analysis) {
    final minutes = analysis.remainingMinutes as int;
    final hours = minutes.abs() ~/ 60;
    final days = hours ~/ 24;
    final amount = days >= 2 ? '$days days' : '$hours h';
    if (minutes < 0) {
      return (label: 'SLA: overdue by $amount', colour: carShareDanger);
    }
    return (
      label: 'SLA: $amount left',
      colour: hours < 24 ? carShareWarning : carShareGreen,
    );
  }

  Widget _evidenceRow(String ticketId, TicketEvidenceItem item) => Row(
    children: [
      item.contentType.startsWith('image/')
          ? _AdminEvidenceThumbnail(ticketId: ticketId, evidence: item)
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
            const SizedBox(height: 2),
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
      IconButton.filledTonal(
        tooltip: 'Analyze evidence',
        style: IconButton.styleFrom(
          backgroundColor: carShareTint,
          foregroundColor: carShareGreenDark,
          minimumSize: const Size(44, 44),
        ),
        onPressed: _working ? null : () => _analyze(item),
        icon: const Icon(Icons.analytics_outlined),
      ),
    ],
  );

  Widget _historyRow(dynamic item, bool last) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(Icons.circle, size: 10, color: carShareGreen),
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

  Widget _actionButtons(TicketStatus status) {
    final buttons = <Widget>[];
    Widget secondary(String label, IconData icon, VoidCallback onTap) =>
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _working ? null : onTap,
          icon: Icon(icon),
          label: Text(label),
        );
    if (status == TicketStatus.open ||
        status == TicketStatus.awaitingResponse ||
        status == TicketStatus.underReview ||
        status == TicketStatus.contested) {
      buttons.add(
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          onPressed: _working ? null : _recordDecision,
          icon: const Icon(Icons.gavel_outlined),
          label: const Text('Record decision'),
        ),
      );
    }
    final others = <Widget>[];
    if (status == TicketStatus.open) {
      others.add(
        secondary(
          'Request response',
          Icons.question_answer_outlined,
          () => _changeStatus('AWAITING_RESPONSE', 'Request a response'),
        ),
      );
    }
    if (status == TicketStatus.open ||
        status == TicketStatus.awaitingResponse ||
        status == TicketStatus.contested) {
      others.add(
        secondary(
          'Start review',
          Icons.manage_search_outlined,
          () => _changeStatus('UNDER_REVIEW', 'Start review'),
        ),
      );
    }
    if (status == TicketStatus.resolved) {
      others.add(
        secondary(
          'Close ticket',
          Icons.lock_outline,
          () => _changeStatus('CLOSED', 'Close ticket'),
        ),
      );
    }
    if (others.isNotEmpty) {
      buttons.add(
        Row(
          children: [
            for (var i = 0; i < others.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: others[i]),
            ],
          ],
        ),
      );
    }
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          buttons[i],
        ],
      ],
    );
  }

  Widget _advancedPanel(AdminSupportTicketDetails details) {
    final advanced = details.advanced;
    if (advanced == null) {
      return const AdminBlock(
        title: 'Analysis',
        icon: Icons.auto_awesome_outlined,
        child: Text(
          'Advanced Support analysis is unavailable.',
          style: TextStyle(color: carShareMuted),
        ),
      );
    }
    final analysis = advanced.analysis;
    TicketAssignmentItem? proposal;
    for (final item in advanced.assignments) {
      if (item.status == 'PROPOSED') {
        proposal = item;
        break;
      }
    }
    final pendingProposal = proposal;
    final positiveSignals = analysis.riskSignals
        .where((item) => !item.negated)
        .toList(growable: false);
    final sla = _slaFromAnalysis(analysis);
    final priority = priorityState(analysis.score);
    return AdminBlock(
      title: 'Priority and analysis',
      icon: Icons.auto_awesome_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminPill(
                'Priority ${priority.label} · ${analysis.score}',
                colour: priority.colour,
                icon: Icons.flag_outlined,
              ),
              AdminPill(
                sla.label,
                colour: sla.colour,
                icon: Icons.timer_outlined,
              ),
              AdminPill(
                'SLA ${humanize(analysis.slaState).toLowerCase()}',
                colour: carShareMuted,
              ),
            ],
          ),
          if (positiveSignals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: carShareWarningTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: supportWarningText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Human review recommended: '
                      '${positiveSignals.map((item) => item.term).join(', ')}',
                      style: const TextStyle(
                        color: supportWarningText,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (advanced.escalations.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...advanced.escalations.map(
              (item) => AdminInfoLine(
                Icons.trending_up_rounded,
                '${humanize(item.type)}: ${item.message}',
                colour: carShareDanger,
              ),
            ),
          ],
          const Divider(height: 28),
          const Text(
            'Assignment',
            style: TextStyle(fontWeight: FontWeight.w800, color: carShareText),
          ),
          const SizedBox(height: 6),
          Text(
            advanced.assignedAgentName == null
                ? 'No agent assigned yet'
                : 'Assigned to ${advanced.assignedAgentName}',
            style: TextStyle(
              color: advanced.assignedAgentName == null
                  ? carShareMuted
                  : carShareText,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (pendingProposal != null)
            AdminInfoLine(
              Icons.person_search_outlined,
              'Proposal: ${pendingProposal.agentName} (${pendingProposal.algorithm}). ${pendingProposal.explanation}',
              maxLines: 6,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: _working
                    ? null
                    : () => _run(
                        () => SupportService.instance.refreshAdminAnalysis(
                          widget.ticketId,
                        ),
                        'Priority and SLA recalculated.',
                      ),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Recalculate'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: _working
                    ? null
                    : () => _run(
                        () => SupportService.instance.proposeAssignment(
                          widget.ticketId,
                        ),
                        'Agent assignment proposed.',
                      ),
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Propose agent'),
              ),
              if (pendingProposal != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: _working
                      ? null
                      : () => _run(
                          () => SupportService.instance.confirmAssignment(
                            widget.ticketId,
                            pendingProposal.id,
                          ),
                          'Agent assignment confirmed.',
                        ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirm agent'),
                ),
            ],
          ),
          const Divider(height: 28),
          // The technical detail stays one tap away, not in the way.
          AdminCollapsible(
            title: 'Show details',
            children: [
              const Text(
                'How the score is made',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Severity ${analysis.severity} x10 + reports ${analysis.reportCount} x5 + '
                'infractions ${analysis.previousInfractions} x3 + waiting '
                '${analysis.waitingHours} h x0.5 = ${analysis.score}',
                style: const TextStyle(color: carShareMuted, height: 1.4),
              ),
              AdminInfoLine(
                Icons.timer_outlined,
                _remainingLabel(analysis.remainingMinutes),
                maxLines: 1,
              ),
              if (advanced.evidenceAnalyses.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Evidence analysis',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: carShareText,
                  ),
                ),
                const SizedBox(height: 4),
                ...advanced.evidenceAnalyses.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${item.isComplete
                          ? 'Complete'
                          : item.isPartial
                          ? 'Partial'
                          : item.status}: '
                      '${item.detectedType ?? 'unknown type'} - '
                      'SHA-256 ${item.sha256.length > 12 ? item.sha256.substring(0, 12) : item.sha256}...'
                      '${item.duplicateEvidenceId == null ? '' : ' - duplicate detected'}'
                      '${item.errorMessage == null ? '' : '\n${item.errorMessage}'}',
                      style: const TextStyle(
                        color: carShareMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
              if (details.tripId != null) ...[
                const SizedBox(height: 14),
                const Text(
                  'Trip context',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: carShareText,
                  ),
                ),
                const SizedBox(height: 6),
                if (advanced.weather != null)
                  Text(
                    _weatherLabel(advanced.weather!),
                    style: const TextStyle(
                      color: carShareMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                if (advanced.geo != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _geoLabel(advanced.geo!),
                    style: const TextStyle(
                      color: carShareMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _routeLabel(advanced.geo!),
                    style: const TextStyle(
                      color: carShareMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (advanced.geo!.routePolyline?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    _SupportRouteMap(geo: advanced.geo!),
                  ],
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _working
                          ? null
                          : () => _run(
                              () => SupportService.instance.refreshWeather(
                                widget.ticketId,
                              ),
                              'Historical weather refreshed.',
                            ),
                      icon: const Icon(Icons.cloud_outlined),
                      label: const Text('Weather'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _working
                          ? null
                          : () => _run(
                              () => SupportService.instance.refreshGeo(
                                widget.ticketId,
                              ),
                              'Geographic context refreshed.',
                            ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Places & route'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'External context helps investigation; it is not automatic proof.',
                  style: TextStyle(color: carShareMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _remainingLabel(int minutes) {
    final hours = minutes.abs() ~/ 60;
    return minutes < 0 ? '$hours h overdue' : '$hours h remaining';
  }

  static String _weatherLabel(TicketWeatherItem weather) {
    if (weather.status != 'AVAILABLE') {
      return weather.errorMessage ?? 'Weather unavailable.';
    }

    final temperature = weather.temperatureC;
    final rain = weather.precipitationMm;
    final wind = weather.windSpeedKmh;
    final details = <String>[];

    if (temperature != null) {
      details.add('a temperature of $temperature degrees Celsius');
    }
    if (rain != null) {
      details.add(
        rain > 0 ? '$rain mm of precipitation' : 'no recorded precipitation',
      );
    }
    if (wind != null) {
      details.add('wind at $wind km/h');
    }

    final context = details.isEmpty
        ? 'Open-Meteo returned no detailed weather measurements.'
        : 'At the trip time and location, Open-Meteo reported '
              '${details.join(', ')}.';

    final hasDifficultConditions =
        (rain != null && rain >= 10) || (wind != null && wind >= 40);
    final hasNoticeableConditions =
        (rain != null && rain > 0) ||
        (wind != null && wind >= 20) ||
        (temperature != null && (temperature <= 5 || temperature >= 35));

    final conclusion = hasDifficultConditions
        ? 'The conditions may have made the trip more difficult.'
        : hasNoticeableConditions
        ? 'Some weather factors may have influenced the trip.'
        : 'The weather appears generally calm and does not indicate a '
              'significant disruption.';

    return '$context\n\nConclusion: $conclusion This information is '
        'investigation context and is not automatic proof.';
  }

  static String _geoLabel(TicketGeoItem geo) {
    final location = geo.actualLat == null
        ? 'No GPS position is available; the planned origin is used.'
        : 'Latest available GPS: ${geo.actualLat}, ${geo.actualLng}.';
    final places = geo.nearbyPlaces ?? 'No nearby-place result is available.';
    final warning = geo.errorMessage == null ? '' : '\n${geo.errorMessage}';
    return '$location\nNearby places: $places$warning\n${geo.source}';
  }

  static String _routeLabel(TicketGeoItem geo) {
    if (geo.idealDistanceM == null || geo.idealDurationS == null) {
      return geo.routeError ?? 'The ideal route has not been estimated yet.';
    }
    final idealKm = (geo.idealDistanceM! / 1000).toStringAsFixed(1);
    final minutes = (geo.idealDurationS! / 60).round();
    final actual = geo.actualDistanceM == null
        ? 'Recorded GPS distance is unavailable.'
        : 'Recorded GPS distance: '
              '${(geo.actualDistanceM! / 1000).toStringAsFixed(1)} km.';
    final verdict = switch (geo.routeVerdict) {
      'CONSISTENT' => 'The recorded trace is consistent with the ideal route.',
      'MINOR_DEVIATION' => 'A minor route deviation was detected.',
      'SIGNIFICANT_DEVIATION' =>
        'A significant route deviation was detected and should be reviewed.',
      'INVALID_GPS' =>
        'The GPS trace is outside the trip area and cannot be validated.',
      _ => 'At least two reliable GPS points are required for validation.',
    };
    return 'OSRM ideal route: $idealKm km, about $minutes min. $actual\n'
        'Conclusion: $verdict';
  }

  static String _date(DateTime? value) =>
      adminDateTime(value, fallback: 'Recently');

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

class _SupportRouteMap extends StatelessWidget {
  const _SupportRouteMap({required this.geo});

  final TicketGeoItem geo;

  @override
  Widget build(BuildContext context) {
    final planned = GeoService.instance
        .decodePolyline(geo.routePolyline)
        .map((point) => LatLng(point[0], point[1]))
        .toList(growable: false);
    final actual = geo.routeVerdict == 'INVALID_GPS'
        ? const <LatLng>[]
        : geo.actualPoints
              .map(
                (point) => LatLng(point.lat.toDouble(), point.lng.toDouble()),
              )
              .toList(growable: false);
    final origin = LatLng(geo.plannedLat.toDouble(), geo.plannedLng.toDouble());
    final destination = LatLng(
      geo.destinationLat?.toDouble() ?? origin.latitude,
      geo.destinationLng?.toDouble() ?? origin.longitude,
    );
    final frame = <LatLng>[origin, destination, ...planned, ...actual];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 210,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(frame),
                  padding: const EdgeInsets.all(32),
                ),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.carshare.app',
                ),
                PolylineLayer(
                  polylines: [
                    if (planned.length > 1)
                      Polyline(
                        points: planned,
                        strokeWidth: 4,
                        color: Colors.blue,
                      ),
                    if (actual.length > 1)
                      Polyline(
                        points: actual,
                        strokeWidth: 4,
                        color: Colors.red,
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: origin,
                      width: 30,
                      height: 30,
                      child: const Icon(
                        Icons.trip_origin,
                        color: carShareGreen,
                        size: 25,
                      ),
                    ),
                    Marker(
                      point: destination,
                      width: 30,
                      height: 30,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.deepOrange,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Wrap(
          spacing: 14,
          children: [
            _MapLegend(color: Colors.blue, label: 'OSRM ideal route'),
            _MapLegend(color: Colors.red, label: 'Recorded GPS trace'),
          ],
        ),
        const Text(
          '© OpenStreetMap contributors',
          style: TextStyle(color: carShareMuted, fontSize: 10),
        ),
      ],
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 18, height: 3, color: color),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 10)),
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

/// What an evidence analysis found: its status, the reason when it is only partial, the file's
/// hash, whether the same file was uploaded elsewhere, and the start of the extracted text.
class _AnalysisSheet extends StatelessWidget {
  const _AnalysisSheet({required this.fileName, required this.result});

  final String fileName;
  final TicketEvidenceAnalysisItem result;

  static const _excerptLength = 500;

  @override
  Widget build(BuildContext context) {
    final text = (result.extractedText ?? '').trim();
    final excerpt = text.length > _excerptLength
        ? '${text.substring(0, _excerptLength)}…'
        : text;
    final colour = result.isComplete ? carShareGreen : carShareWarning;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Evidence analysis',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    result.isComplete
                        ? 'Complete'
                        : result.isPartial
                        ? 'Partial'
                        : result.status,
                    style: TextStyle(
                      color: colour,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(fileName, style: const TextStyle(color: carShareMuted)),
            if (result.errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: carShareWarning.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(result.errorMessage!),
              ),
            ],
            const SizedBox(height: 14),
            _AnalysisRow('Detected type', result.detectedType ?? 'Unknown'),
            _AnalysisRow(
              'Duplicate',
              result.duplicateEvidenceId == null
                  ? 'No other upload has the same file'
                  : 'The same file was uploaded elsewhere on the platform',
            ),
            _AnalysisRow('SHA-256', result.sha256, mono: true),
            _AnalysisRow(
              'Extracted text',
              excerpt.isEmpty
                  ? (result.isPartial
                        ? 'None: the text could not be read this time.'
                        : 'No text was found in this file.')
                  : excerpt,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisRow extends StatelessWidget {
  const _AnalysisRow(this.label, this.value, {this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: carShareMuted,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: mono ? 12 : 14,
            fontFamily: mono ? 'monospace' : null,
          ),
        ),
      ],
    ),
  );
}
