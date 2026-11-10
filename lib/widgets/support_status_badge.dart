import 'package:flutter/material.dart';

import '../models/support_ticket.dart';
import '../theme.dart';

class SupportStatusBadge extends StatelessWidget {
  const SupportStatusBadge({super.key, required this.status});

  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      TicketStatus.awaitingResponse => (
        'Awaiting response',
        supportWarningBackground,
        supportWarningText,
      ),
      TicketStatus.underReview => (
        'Under review',
        carShareTint,
        supportDarkGreen,
      ),
      TicketStatus.resolved => ('Resolved', carShareTint, supportDarkGreen),
      TicketStatus.closed => ('Closed', carShareBackground, carShareMuted),
      TicketStatus.contested => (
        'Contested',
        supportWarningBackground,
        supportWarningText,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
