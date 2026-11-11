import 'package:flutter/material.dart';

import '../../models/support_ticket.dart';
import '../../theme.dart';
import '../../widgets/support_status_badge.dart';

class TicketDetailsPage extends StatelessWidget {
  const TicketDetailsPage({super.key, required this.ticket});
  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: carShareBackground,
      surfaceTintColor: carShareBackground,
      title: Text(ticket.reference, style: const TextStyle(fontWeight: FontWeight.w800, color: carShareText)),
      actions: [Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: SupportStatusBadge(status: ticket.status)))],
    ),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        Text(ticket.category.toUpperCase(), style: const TextStyle(color: supportDarkGreen, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(ticket.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: carShareText)),
        const SizedBox(height: 5),
        Text('${ticket.trip} · ${ticket.createdLabel}', style: const TextStyle(color: carShareMuted)),
        const SizedBox(height: 18),
        Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(14), border: Border.all(color: carShareBorder)),
          child: Text(ticket.description, style: const TextStyle(color: carShareText, height: 1.45))),
        const SizedBox(height: 18),
        Row(children: [
          Icon(ticket.isResolved ? Icons.check_circle_outline : Icons.support_agent_outlined, color: supportGreen),
          const SizedBox(width: 8), Expanded(child: Text(ticket.summary, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        if (ticket.resolution != null && ticket.resolution!.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Resolution', style: TextStyle(color: carShareText, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(ticket.resolution!, style: const TextStyle(color: carShareMuted, height: 1.4)),
        ],
      ]),
    ))),
  );
}
