import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/support_ticket.dart';
import '../../services/auth_service.dart';
import '../../services/support_service.dart';
import '../../theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/round_back_button.dart';
import '../../widgets/support_ticket_card.dart';
import 'report_problem_page.dart';
import 'support_notifications_page.dart';
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
  late Future<List<SupportTicket>> _tickets = _loadTickets();
  Timer? _notificationTimer;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadNotifications();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadUnreadNotifications(),
    );
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final count = await SupportService.instance.unreadNotificationCount();
      if (mounted) setState(() => _unreadNotifications = count);
    } catch (_) {
      // Tickets remain usable if the notification count is temporarily unavailable.
    }
  }

  Future<List<SupportTicket>> _loadTickets() async {
    final user = AuthService.instance.currentUser.value;
    if (user == null) return const [];
    return SupportService.instance.tickets(user.id);
  }

  void _refresh() {
    final tickets = _loadTickets();
    setState(() {
      _tickets = tickets;
    });
    _loadUnreadNotifications();
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SupportNotificationsPage()),
    );
    if (mounted) _loadUnreadNotifications();
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _newTicket() async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ReportProblemPage()),
    );
    if (!mounted) return;
    _refresh();
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openDetails(SupportTicket ticket) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TicketDetailsPage(ticket: ticket),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: roundBackAppBar(
      context,
      onBack: widget.onNavigateToTab == null
          ? null
          : () => widget.onNavigateToTab!(3),
      title: 'Support',
      actions: [
        IconButton(
          tooltip: 'Support notifications',
          onPressed: _openNotifications,
          icon: Badge(
            isLabelVisible: _unreadNotifications > 0,
            label: Text('$_unreadNotifications'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
        IconButton(
          tooltip: _searchOpen ? 'Close search' : 'Search tickets',
          onPressed: () => setState(() {
            _searchOpen = !_searchOpen;
            if (!_searchOpen) _searchController.clear();
          }),
          icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: FutureBuilder<List<SupportTicket>>(
      future: _tickets,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load your tickets',
                    line: authErrorMessage(snapshot.error!),
                  ),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }

        final allTickets = snapshot.data ?? const <SupportTicket>[];
        final query = _searchController.text.trim().toLowerCase();
        final tickets = allTickets
            .where((ticket) {
              final tabMatches = _showOpen
                  ? !ticket.isResolved
                  : ticket.isResolved;
              final text =
                  '${ticket.reference} ${ticket.category} ${ticket.title} ${ticket.description} ${ticket.trip}'
                      .toLowerCase();
              return tabMatches && (query.isEmpty || text.contains(query));
            })
            .toList(growable: false);

        return SafeArea(
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
                          openCount: allTickets
                              .where((ticket) => !ticket.isResolved)
                              .length,
                          resolvedCount: allTickets
                              .where((ticket) => ticket.isResolved)
                              .length,
                          onChanged: (value) =>
                              setState(() => _showOpen = value),
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
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SupportTicketCard(
                              ticket: tickets[index],
                              onTap: () => _openDetails(tickets[index]),
                            ),
                          ),
                          childCount: tickets.length,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 92)),
                ],
              ),
            ),
          ),
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: supportGreen,
      foregroundColor: Colors.white,
      onPressed: _newTicket,
      icon: const Icon(Icons.add),
      label: const Text(
        'New ticket',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
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
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [carShareCardShadow],
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
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.support_agent_outlined,
    title: showOpen ? 'No open tickets' : 'No resolved tickets',
    line: 'Your support requests will appear here.',
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? supportGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : carShareMuted,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
