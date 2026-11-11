import 'package:flutter/material.dart';

import '../../models/support_ticket.dart';
import '../../theme.dart';
import '../../widgets/support_ticket_card.dart';
import 'report_problem_page.dart';
import 'ticket_details_page.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key, this.onNavigateToTab});

  final ValueChanged<int>? onNavigateToTab;

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  bool _showOpen = true;
  bool _searchOpen = false;
  final _searchController = TextEditingController();

  static const _tickets = [
    SupportTicket(
      reference: 'DSP-2026-0142',
      category: 'Driver was late',
      title: 'Late arrival at pickup',
      description: 'The driver arrived 25 minutes after the scheduled pickup.',
      trip: 'Ennasr 2 → Lac 2',
      createdLabel: 'Today',
      status: TicketStatus.awaitingResponse,
      summary: 'Ahmed has 31h left to respond',
      responseDeadline: 'Ahmed has 31h left to give his statement',
    ),
    SupportTicket(
      reference: 'DSP-2026-0127',
      category: 'Wrong route taken',
      title: 'A longer route was taken',
      description: 'The trip took a different route than the one planned.',
      trip: 'Lac 2 → Ennasr 2',
      createdLabel: '2 Oct',
      status: TicketStatus.underReview,
      summary: 'A support agent is reviewing',
    ),
    SupportTicket(
      reference: 'DSP-2026-0098',
      category: 'Vehicle condition',
      title: 'Air conditioning was not working',
      description: 'The vehicle condition did not match what was expected.',
      trip: 'Ariana → Charguia 2',
      createdLabel: '28 Sep',
      status: TicketStatus.resolved,
      summary: 'Decision: warning issued to driver',
    ),
    SupportTicket(
      reference: 'DSP-2026-0081',
      category: 'Behaviour issue',
      title: 'Concern about conduct during the trip',
      description: 'The report was reviewed and the case is now closed.',
      trip: 'Tunis Centre → La Marsa',
      createdLabel: '21 Sep',
      status: TicketStatus.closed,
      summary: 'The support case has been closed',
    ),
    SupportTicket(
      reference: 'DSP-2026-0064',
      category: 'Passenger was absent',
      title: 'Decision has been contested',
      description: 'A party requested a second review of the decision.',
      trip: 'Lac 2 → Ariana',
      createdLabel: '15 Sep',
      status: TicketStatus.contested,
      summary: 'A second review is in progress',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final tickets = _tickets
        .where((ticket) {
          final inTab = _showOpen ? !ticket.isResolved : ticket.isResolved;
          final matchesQuery =
              query.isEmpty ||
              '${ticket.reference} ${ticket.category} ${ticket.title} '
                      '${ticket.description} ${ticket.trip}'
                  .toLowerCase()
                  .contains(query);
          return inTab && matchesQuery;
        })
        .toList(growable: false);

    return Scaffold(
      backgroundColor: carShareBackground,
      appBar: AppBar(
        backgroundColor: carShareBackground,
        surfaceTintColor: carShareBackground,
        leading: widget.onNavigateToTab == null
            ? null
            : IconButton(
                tooltip: 'Back to profile',
                onPressed: () => widget.onNavigateToTab!(3),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: const Text(
          'Support',
          style: TextStyle(fontWeight: FontWeight.w800, color: carShareText),
        ),
        actions: [
          IconButton(
            tooltip: _searchOpen ? 'Close search' : 'Search tickets',
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _searchController.clear();
            }),
            icon: Icon(
              _searchOpen ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (_searchOpen) ...[
                        TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Search tickets',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _TicketTabs(
                        showOpen: _showOpen,
                        openCount: _tickets
                            .where((ticket) => !ticket.isResolved)
                            .length,
                        resolvedCount: _tickets
                            .where((ticket) => ticket.isResolved)
                            .length,
                        onChanged: (value) => setState(() => _showOpen = value),
                      ),
                      const SizedBox(height: 18),
                    ]),
                  ),
                ),
                if (tickets.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyTickets(showOpen: _showOpen),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final ticket = tickets[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SupportTicketCard(
                            ticket: ticket,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TicketDetailsPage(ticket: ticket),
                              ),
                            ),
                          ),
                        );
                      }, childCount: tickets.length),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 92)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: supportGreen,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ReportProblemPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text(
          'New ticket',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _TicketTabs extends StatelessWidget {
  const _TicketTabs({
    required this.showOpen,
    required this.openCount,
    required this.resolvedCount,
    required this.onChanged,
  });

  final bool showOpen;
  final int openCount;
  final int resolvedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: carShareBorder),
    ),
    child: Row(
      children: [
        _TabButton(
          label: 'Open ($openCount)',
          selected: showOpen,
          onTap: () => onChanged(true),
        ),
        _TabButton(
          label: 'Resolved ($resolvedCount)',
          selected: !showOpen,
          onTap: () => onChanged(false),
        ),
      ],
    ),
  );
}

class _EmptyTickets extends StatelessWidget {
  const _EmptyTickets({required this.showOpen});

  final bool showOpen;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.support_agent_outlined,
            color: supportGreen,
            size: 38,
          ),
          const SizedBox(height: 12),
          Text(
            showOpen ? 'No open tickets' : 'No resolved tickets',
            style: const TextStyle(
              color: carShareText,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Your support requests will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: carShareMuted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? supportGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : carShareMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
