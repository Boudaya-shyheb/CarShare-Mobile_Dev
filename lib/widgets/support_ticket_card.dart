import 'package:flutter/material.dart';

import '../models/support_ticket.dart';
import '../theme.dart';
import 'status_chip.dart';
import 'support_status_badge.dart';

class SupportTicketCard extends StatelessWidget {
  const SupportTicketCard({
    super.key,
    required this.ticket,
    required this.onTap,
  });

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CarShareCard(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                ticket.reference,
                style: const TextStyle(
                  color: carShareMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SupportStatusBadge(status: ticket.status),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          ticket.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: carShareText,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${ticket.trip} · ${ticket.createdLabel}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: carShareMuted,
            fontSize: 13,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: carShareBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                switch (ticket.status) {
                  TicketStatus.open ||
                  TicketStatus.awaitingResponse => Icons.hourglass_top_rounded,
                  TicketStatus.underReview ||
                  TicketStatus.contested => Icons.manage_search_rounded,
                  TicketStatus.resolved ||
                  TicketStatus.closed => Icons.verified_outlined,
                  TicketStatus.withdrawn => Icons.cancel_outlined,
                },
                size: 18,
                color: switch (ticket.status) {
                  TicketStatus.open ||
                  TicketStatus.awaitingResponse => supportWarningText,
                  TicketStatus.underReview ||
                  TicketStatus.contested => supportDarkGreen,
                  TicketStatus.resolved || TicketStatus.closed => supportGreen,
                  TicketStatus.withdrawn => carShareMuted,
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ticket.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: carShareText,
                    height: 1.3,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: carShareMuted),
            ],
          ),
        ),
      ],
    ),
  );
}
