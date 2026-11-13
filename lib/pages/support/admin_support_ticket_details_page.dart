import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/support_ticket.dart';
import '../../models/support_ticket_detail.dart';
import '../../services/support_service.dart';
import '../../services/geo_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
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
              const SizedBox(height: 12),
              _advancedPanel(details),
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
                    trailing: IconButton(
                      tooltip: 'Analyze evidence',
                      onPressed: _working ? null : () => _analyze(item),
                      icon: const Icon(Icons.analytics_outlined),
                    ),
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

  Widget _advancedPanel(AdminSupportTicketDetails details) {
    final advanced = details.advanced;
    if (advanced == null) {
      return const _Panel(
        child: Text('Advanced Support analysis is unavailable.'),
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
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: supportGreen),
              SizedBox(width: 8),
              Text(
                'Advanced Support engine',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: 'Priority ${analysis.score}'),
              _InfoChip(label: 'SLA ${analysis.slaState.replaceAll('_', ' ')}'),
              _InfoChip(label: _remainingLabel(analysis.remainingMinutes)),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Score: severity ${analysis.severity} x10 + reports '
            '${analysis.reportCount} x5 + infractions '
            '${analysis.previousInfractions} x3 + waiting '
            '${analysis.waitingHours} h x0.5',
            style: const TextStyle(color: carShareMuted, fontSize: 12),
          ),
          if (positiveSignals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Human review recommended: '
              '${positiveSignals.map((item) => item.term).join(', ')}',
              style: const TextStyle(
                color: Colors.deepOrange,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (advanced.escalations.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...advanced.escalations.map(
              (item) => Text(
                '- ${item.type.replaceAll('_', ' ')}: ${item.message}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          const Divider(height: 24),
          Text(
            advanced.assignedAgentName == null
                ? 'Assigned agent: none'
                : 'Assigned agent: ${advanced.assignedAgentName}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (pendingProposal != null)
            Text(
              'Proposal: ${pendingProposal.agentName} '
              '(${pendingProposal.algorithm})\n${pendingProposal.explanation}',
              style: const TextStyle(color: carShareMuted, fontSize: 12),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              OutlinedButton.icon(
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
          if (advanced.evidenceAnalyses.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Evidence analysis',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            ...advanced.evidenceAnalyses.map(
              (item) => Text(
                '${item.isComplete ? 'Complete' : item.isPartial ? 'Partial' : item.status}: '
                '${item.detectedType ?? 'unknown type'} - '
                'SHA-256 ${item.sha256.length > 12 ? item.sha256.substring(0, 12) : item.sha256}...'
                '${item.duplicateEvidenceId == null ? '' : ' - duplicate detected'}'
                '${item.errorMessage == null ? '' : '\n${item.errorMessage}'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          if (details.tripId != null) ...[
            const Divider(height: 24),
            const Text(
              'Trip context',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            if (advanced.weather != null)
              Text(
                _weatherLabel(advanced.weather!),
                style: const TextStyle(fontSize: 12),
              ),
            if (advanced.geo != null) ...[
              const SizedBox(height: 10),
              Text(
                _geoLabel(advanced.geo!),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Text(
                _routeLabel(advanced.geo!),
                style: const TextStyle(fontSize: 12),
              ),
              if (advanced.geo!.routePolyline?.isNotEmpty == true) ...[
                const SizedBox(height: 9),
                _SupportRouteMap(geo: advanced.geo!),
              ],
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
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
            const SizedBox(height: 5),
            const Text(
              'External context helps investigation; it is not automatic proof.',
              style: TextStyle(color: carShareMuted, fontSize: 11),
            ),
          ],
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: carShareTint,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: supportDarkGreen,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
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
                    style: TextStyle(color: colour, fontWeight: FontWeight.w800),
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
