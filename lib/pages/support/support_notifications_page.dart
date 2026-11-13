import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/support_notification.dart';
import '../../models/support_ticket.dart';
import '../../services/auth_service.dart';
import '../../services/support_service.dart';
import '../../theme.dart';
import '../../widgets/notification_filter_bar.dart';
import 'ticket_details_page.dart';

class SupportNotificationsPage extends StatefulWidget {
  const SupportNotificationsPage({super.key, this.embedded = false});

  /// True inside the unified notifications page: just the list, no Scaffold or app bar.
  final bool embedded;

  @override
  State<SupportNotificationsPage> createState() =>
      _SupportNotificationsPageState();
}

class _SupportNotificationsPageState extends State<SupportNotificationsPage> {
  late Future<List<SupportNotificationItem>> _notifications = _load();
  final Set<String> _readingIds = {};
  Timer? _liveRefreshTimer;
  bool _showUnreadOnly = false;

  @override
  void initState() {
    super.initState();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      try {
        await _refresh();
      } catch (_) {
        // Keep the last visible notifications when the network is temporarily unavailable.
      }
    });
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  Future<List<SupportNotificationItem>> _load() =>
      SupportService.instance.notifications();

  Future<void> _refresh() async {
    final notifications = _load();
    setState(() {
      _notifications = notifications;
    });
    await notifications;
  }

  Future<void> _openTicket(SupportNotificationItem item) async {
    if (_readingIds.contains(item.id)) return;
    setState(() {
      _readingIds.add(item.id);
    });
    try {
      if (!item.read) {
        await SupportService.instance.markNotificationRead(item.id);
      }
      final user = AuthService.instance.currentUser.value;
      if (user == null) throw StateError('Please sign in again.');
      final tickets = await SupportService.instance.tickets(user.id);
      SupportTicket? selectedTicket;
      for (final ticket in tickets) {
        if (ticket.id == item.ticketId) {
          selectedTicket = ticket;
          break;
        }
      }
      if (selectedTicket == null) {
        throw StateError('This ticket is no longer available.');
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => TicketDetailsPage(ticket: selectedTicket!),
        ),
      );
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _readingIds.remove(item.id);
        });
      }
    }
  }

  Widget _buildList() => FutureBuilder<List<SupportNotificationItem>>(
    future: _notifications,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const Center(
          child: CircularProgressIndicator(color: supportGreen),
        );
      }
      if (snapshot.hasError) {
        return _ErrorState(error: snapshot.error, onRetry: _refresh);
      }
      final rows = snapshot.data ?? const <SupportNotificationItem>[];
      final unreadCount = rows.where((item) => !item.read).length;
      final visibleRows = _showUnreadOnly
          ? rows.where((item) => !item.read).toList(growable: false)
          : rows;
      return RefreshIndicator(
        onRefresh: _refresh,
        color: supportGreen,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              sliver: SliverToBoxAdapter(
                child: _NotificationsHeader(
                  totalCount: rows.length,
                  unreadCount: unreadCount,
                  showUnreadOnly: _showUnreadOnly,
                  onFilterChanged: (value) => setState(() {
                    _showUnreadOnly = value;
                  }),
                ),
              ),
            ),
            if (visibleRows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(filtered: _showUnreadOnly),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: visibleRows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = visibleRows[index];
                    return _NotificationCard(
                      item: item,
                      markingRead: _readingIds.contains(item.id),
                      onTap: () => _openTicket(item),
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildList();
    return Scaffold(
      backgroundColor: carShareBackground,
      appBar: AppBar(
        backgroundColor: carShareBackground,
        surfaceTintColor: carShareBackground,
        title: const Text(
          'Support notifications',
          style: TextStyle(fontWeight: FontWeight.w800, color: carShareText),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildList(),
    );
  }
}

/// "3 unread of 5" and the All / Unread switch: the same bar on both notification tabs.
class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({
    required this.totalCount,
    required this.unreadCount,
    required this.showUnreadOnly,
    required this.onFilterChanged,
  });
  final int totalCount;
  final int unreadCount;
  final bool showUnreadOnly;
  final ValueChanged<bool> onFilterChanged;

  @override
  Widget build(BuildContext context) => NotificationFilterBar(
    summary: unreadCount == 0
        ? 'You are all caught up'
        : '$unreadCount unread of $totalCount',
    showUnreadOnly: showUnreadOnly,
    onChanged: onFilterChanged,
  );
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.markingRead,
    required this.onTap,
  });
  final SupportNotificationItem item;
  final bool markingRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final appearance = _appearance(item.type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: item.read ? Colors.white : const Color(0xFFF0FDF8),
            borderRadius: BorderRadius.circular(16),
            border: item.read
                ? null
                : Border.all(color: supportGreen.withValues(alpha: 0.35)),
            boxShadow: const [carShareCardShadow],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: appearance.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(appearance.icon, color: appearance.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              color: carShareText,
                              fontSize: 15,
                              fontWeight: item.read
                                  ? FontWeight.w700
                                  : FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!item.read) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: const BoxDecoration(
                              color: supportGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.message,
                      style: const TextStyle(
                        color: carShareMuted,
                        height: 1.4,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: carShareTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.ticketReference,
                            style: const TextStyle(
                              color: supportDarkGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (markingRead)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _notificationDate(item.createdAt),
                                style: const TextStyle(
                                  color: carShareMuted,
                                  fontSize: 10.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: carShareMuted,
                                size: 16,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              color: carShareTint,
              shape: BoxShape.circle,
            ),
            child: Icon(
              filtered
                  ? Icons.mark_email_read_outlined
                  : Icons.notifications_none_rounded,
              color: supportGreen,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            filtered ? 'No unread notifications' : 'No notifications yet',
            style: const TextStyle(
              color: carShareText,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'You have reviewed every support update.'
                : 'Updates about your tickets will appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: carShareMuted, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Notifications are unavailable',
            style: TextStyle(
              color: carShareText,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

_NotificationAppearance _appearance(String type) => switch (type) {
  'EVIDENCE_ADDED' => const _NotificationAppearance(
    Icons.attach_file_rounded,
    Colors.indigo,
  ),
  'STATEMENT_ADDED' || 'STATEMENT_UPDATED' => const _NotificationAppearance(
    Icons.forum_outlined,
    Colors.blue,
  ),
  'DECISION_RECORDED' => const _NotificationAppearance(
    Icons.gavel_rounded,
    Colors.deepPurple,
  ),
  'TICKET_CONTESTED' => const _NotificationAppearance(
    Icons.report_problem_outlined,
    carShareWarning,
  ),
  _ => const _NotificationAppearance(Icons.sync_alt_rounded, supportGreen),
};

String _notificationDate(DateTime? value) {
  if (value == null) return 'Recently';
  final difference = DateTime.now().difference(value);
  if (!difference.isNegative && difference.inMinutes < 1) return 'Just now';
  if (!difference.isNegative && difference.inMinutes < 60) {
    return '${difference.inMinutes} min ago';
  }
  if (!difference.isNegative && difference.inHours < 24) {
    return '${difference.inHours} h ago';
  }
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class _NotificationAppearance {
  const _NotificationAppearance(this.icon, this.color);
  final IconData icon;
  final Color color;
}
