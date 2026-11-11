import 'package:flutter/material.dart';

import '../../models/support_ticket.dart';
import '../../theme.dart';
import '../../widgets/support_evidence_section.dart';
import '../../widgets/support_status_badge.dart';

class TicketDetailsPage extends StatefulWidget {
  const TicketDetailsPage({super.key, required this.ticket});

  final SupportTicket ticket;

  @override
  State<TicketDetailsPage> createState() => _TicketDetailsPageState();
}

class _TicketDetailsPageState extends State<TicketDetailsPage> {
  final _evidenceController = SupportEvidenceController(
    initialEvidence: const [
      SupportEvidence(name: 'arrival-time-photo.jpg', isImage: true),
      SupportEvidence(name: 'trip-statement.pdf', isImage: false),
    ],
  );

  SupportTicket get ticket => widget.ticket;

  @override
  void dispose() {
    _evidenceController.dispose();
    super.dispose();
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
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ticket.category,
                      style: const TextStyle(
                        color: supportDarkGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    ticket.createdLabel,
                    style: const TextStyle(color: carShareMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                ticket.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
              const SizedBox(height: 4),
              Text(ticket.trip, style: const TextStyle(color: carShareMuted)),
              const SizedBox(height: 8),
              Text(
                ticket.description,
                style: const TextStyle(
                  color: carShareText,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              _Timeline(status: ticket.status),
              const SizedBox(height: 18),
              if (ticket.responseDeadline != null)
                _DeadlineBanner(text: ticket.responseDeadline!),
              if (ticket.responseDeadline != null) const SizedBox(height: 18),
              const _SectionLabel('Trip data · auto-attached'),
              const SizedBox(height: 8),
              const _TripDataCard(),
              const SizedBox(height: 20),
              const _SectionLabel('Statements'),
              const SizedBox(height: 8),
              const _StatementCard(
                title: 'You · Today 10:02',
                message: 'The driver arrived at 08:40 instead of 08:15 and I missed my exam start.',
                mine: true,
              ),
              const SizedBox(height: 10),
              if (ticket.status == TicketStatus.awaitingResponse)
                const _WaitingStatement()
              else
                const _StatementCard(
                  title: 'Ahmed · Today 11:24',
                  message: 'There was unexpected traffic on the way to the pickup point.',
                  mine: false,
                ),
              const SizedBox(height: 20),
              SupportEvidenceSection(controller: _evidenceController),
            ],
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () =>
                  _showDemoMessage(context, 'Withdraw is a UI demonstration.'),
              child: const Text('Withdraw'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: supportGreen),
              onPressed: () => _evidenceController.showPickerOptions(context),
              child: const Text('Add evidence'),
            ),
          ),
        ],
      ),
    ),
  );

  void _showDemoMessage(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final currentStep = switch (status) {
      TicketStatus.awaitingResponse => 1,
      TicketStatus.underReview || TicketStatus.contested => 2,
      TicketStatus.resolved || TicketStatus.closed => 3,
    };

    return Row(
      children: [
        for (var index = 0; index < 4; index++) ...[
          _TimelineStep(
            label: const [
              'Open',
              'Awaiting\nresponse',
              'Under review',
              'Resolved',
            ][index],
            done: index < currentStep,
            active: index == currentStep,
          ),
          if (index < 3) _TimelineLine(done: index < currentStep),
        ],
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(
        done
            ? Icons.check_circle
            : active
            ? Icons.radio_button_checked
            : Icons.circle_outlined,
        size: 19,
        color: done || active ? supportGreen : carShareBorder,
      ),
      const SizedBox(height: 5),
      SizedBox(
        width: 47,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            height: 1.1,
            color: done || active ? supportDarkGreen : carShareMuted,
            fontWeight: done || active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

class _TimelineLine extends StatelessWidget {
  const _TimelineLine({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 24),
      color: done ? supportGreen : carShareBorder,
    ),
  );
}

class _DeadlineBanner extends StatelessWidget {
  const _DeadlineBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: supportWarningBackground,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.hourglass_top_rounded, color: supportWarningText),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: supportWarningText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: carShareText,
      fontSize: 13,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _TripDataCard extends StatelessWidget {
  const _TripDataCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: carShareBorder),
    ),
    child: const Column(
      children: [
        Row(
          children: [
            Icon(Icons.storage_outlined, size: 18, color: supportGreen),
            SizedBox(width: 7),
            Expanded(
              child: Text(
                'Trip data · auto-attached',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _ReadOnlyBadge(),
          ],
        ),
        SizedBox(height: 12),
        _Fact(label: 'Scheduled pickup', value: '08:15'),
        _Fact(
          label: 'Driver arrived',
          value: '08:40 · +25 min',
          valueColor: carShareDanger,
        ),
        _Fact(label: 'Route deviation', value: 'No deviation'),
        _Fact(label: 'GPS at pickup', value: '36.8991, 10.1862'),
        _Fact(label: 'Trip events', value: '12 location updates'),
      ],
    ),
  );
}

class _ReadOnlyBadge extends StatelessWidget {
  const _ReadOnlyBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: carShareBackground,
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      'Read-only',
      style: TextStyle(
        fontSize: 9,
        color: carShareMuted,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.valueColor = carShareText,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: carShareMuted),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: valueColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({
    required this.title,
    required this.message,
    required this.mine,
  });

  final String title;
  final String message;
  final bool mine;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: mine ? carShareTint : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: mine ? carShareTint : carShareBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: supportDarkGreen,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          style: const TextStyle(
            fontSize: 12,
            height: 1.35,
            color: carShareText,
          ),
        ),
      ],
    ),
  );
}

class _WaitingStatement extends StatelessWidget {
  const _WaitingStatement();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: carShareBorder, style: BorderStyle.solid),
    ),
    child: const Row(
      children: [
        Icon(Icons.schedule_outlined, size: 18, color: carShareMuted),
        SizedBox(width: 9),
        Text(
          "Waiting for Ahmed's statement…",
          style: TextStyle(fontSize: 12, color: carShareMuted),
        ),
      ],
    ),
  );
}
