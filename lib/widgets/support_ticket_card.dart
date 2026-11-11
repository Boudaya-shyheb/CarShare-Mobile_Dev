import 'package:flutter/material.dart';

import '../models/support_ticket.dart';
import '../theme.dart';
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
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: carShareBorder),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SupportStatusBadge(status: ticket.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              ticket.category,
              style: const TextStyle(
                color: supportDarkGreen,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ticket.title,
              style: const TextStyle(
                color: carShareText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ticket.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: carShareMuted,
                fontSize: 12,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.route_outlined,
                  size: 15,
                  color: carShareMuted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    ticket.trip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: carShareMuted, fontSize: 11),
                  ),
                ),
                Text(
                  ticket.createdLabel,
                  style: const TextStyle(color: carShareMuted, fontSize: 11),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 11),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Icon(
                  switch (ticket.status) {
                    TicketStatus.awaitingResponse =>
                      Icons.hourglass_top_rounded,
                    TicketStatus.underReview ||
                    TicketStatus.contested => Icons.manage_search_rounded,
                    TicketStatus.resolved ||
                    TicketStatus.closed => Icons.verified_outlined,
                  },
                  size: 15,
                  color: switch (ticket.status) {
                    TicketStatus.awaitingResponse => supportWarningText,
                    TicketStatus.underReview ||
                    TicketStatus.contested => supportDarkGreen,
                    TicketStatus.resolved ||
                    TicketStatus.closed => supportGreen,
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ticket.summary,
                    style: const TextStyle(fontSize: 11, color: carShareText),
                  ),
                ),
                const Icon(Icons.chevron_right, color: carShareMuted),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
