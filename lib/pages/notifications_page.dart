import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/lost_and_found_notification.dart';
import '../services/auth_service.dart';
import '../services/lost_and_found_notification_service.dart';
import '../services/support_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_filter_bar.dart';
import '../widgets/resume_refresh.dart';
import '../widgets/round_back_button.dart';
import 'lost_and_found_page.dart';
import 'support/support_notifications_page.dart';

/// The Home bell: one page for every kind of notification, with a chip per source, Support
/// (the existing page, embedded as it is) and Lost & Found. Each chip shows its own unread count.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.userId});

  final String userId;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _tabSupport = 0;
  static const _tabLostAndFound = 1;

  int _tab = _tabSupport;
  bool _tabChosen = false;
  int _supportUnread = 0;
  int _lostAndFoundUnread = 0;
  bool _marking = false;
  bool _lfUnreadOnly = false;
  late Future<List<LostAndFoundNotification>> _lostAndFound =
      _loadLostAndFound();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshCounts();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshAll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<List<LostAndFoundNotification>> _loadLostAndFound() =>
      LostAndFoundNotificationService.instance.list();

  /// On open, on resume, on pull-to-refresh and every 15 seconds while the page is on screen.
  Future<void> _refreshAll() async {
    if (!mounted) return;
    final next = _loadLostAndFound();
    setState(() {
      _lostAndFound = next;
    });
    await _refreshCounts();
    try {
      await next;
    } catch (_) {
      // The tab shows its own error; the counts above are best effort.
    }
  }

  Future<void> _refreshCounts() async {
    var support = _supportUnread;
    var lostAndFound = _lostAndFoundUnread;
    try {
      support = await SupportService.instance.unreadNotificationCount();
    } catch (_) {}
    try {
      lostAndFound = await LostAndFoundNotificationService.instance
          .unreadCount();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _supportUnread = support;
      _lostAndFoundUnread = lostAndFound;
      // The first time the counts arrive, open on the source that has something new.
      if (!_tabChosen) {
        _tabChosen = true;
        if (lostAndFound > 0 && support == 0) _tab = _tabLostAndFound;
      }
    });
  }

  Future<void> _markAllRead() async {
    setState(() => _marking = true);
    try {
      await LostAndFoundNotificationService.instance.markAllRead();
      final support = await SupportService.instance.notifications();
      for (final item in support.where((item) => !item.read)) {
        await SupportService.instance.markNotificationRead(item.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _marking = false);
        await _refreshAll();
      }
    }
  }

  Future<void> _open(LostAndFoundNotification item) async {
    try {
      if (!item.read) {
        await LostAndFoundNotificationService.instance.markRead(item.id);
      }
    } catch (_) {
      // Opening the report matters more than the read mark.
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LostAndFoundPage(
          key: ValueKey('${widget.userId}-${item.reportId}'),
          userId: widget.userId,
          initialReportId: item.reportId,
        ),
      ),
    );
    if (mounted) await _refreshAll();
  }

  @override
  Widget build(BuildContext context) => ResumeRefresh(
    onResume: _refreshAll,
    child: Scaffold(
      backgroundColor: carShareBackground,
      appBar: roundBackAppBar(
        context,
        title: 'Notifications',
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            onPressed: _marking ? null : _markAllRead,
            icon: const Icon(Icons.done_all_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _SourceChip(
                  label: 'Support',
                  unread: _supportUnread,
                  selected: _tab == _tabSupport,
                  onTap: () => setState(() {
                    _tab = _tabSupport;
                    _tabChosen = true;
                  }),
                ),
                const SizedBox(width: 10),
                _SourceChip(
                  label: 'Lost & Found',
                  unread: _lostAndFoundUnread,
                  selected: _tab == _tabLostAndFound,
                  onTap: () => setState(() {
                    _tab = _tabLostAndFound;
                    _tabChosen = true;
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                const SupportNotificationsPage(embedded: true),
                _buildLostAndFound(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildLostAndFound() => FutureBuilder<List<LostAndFoundNotification>>(
    future: _lostAndFound,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load the updates',
              line: authErrorMessage(snapshot.error!),
            ),
            Center(
              child: OutlinedButton(
                onPressed: _refreshAll,
                child: const Text('Try again'),
              ),
            ),
          ],
        );
      }
      final all = snapshot.data ?? const <LostAndFoundNotification>[];
      final unread = all.where((item) => !item.read).length;
      final rows = _lfUnreadOnly
          ? all.where((item) => !item.read).toList(growable: false)
          : all;
      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            NotificationFilterBar(
              summary: unread == 0
                  ? 'You are all caught up'
                  : '$unread unread of ${all.length}',
              showUnreadOnly: _lfUnreadOnly,
              onChanged: (value) => setState(() => _lfUnreadOnly = value),
            ),
            const SizedBox(height: 14),
            if (rows.isEmpty)
              EmptyState(
                icon: Icons.notifications_none_rounded,
                title: all.isEmpty
                    ? 'No Lost & Found updates yet'
                    : 'Nothing unread',
                line: all.isEmpty
                    ? 'You will hear about matches, meetings and returns here.'
                    : 'Switch to All to see earlier updates.',
              )
            else
              for (final item in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _NotificationCard(
                    item: item,
                    onTap: () => _open(item),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.unread,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int unread;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? carShareGreen : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? carShareGreen : carShareBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : carShareText,
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white : carShareDanger,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$unread',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? carShareGreen : Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final LostAndFoundNotification item;
  final VoidCallback onTap;

  static IconData _icon(String type) => switch (type) {
    'MATCH_FOUND' => Icons.travel_explore_rounded,
    'MATCH_CONFIRMED' => Icons.handshake_outlined,
    'MEETING_ARRANGED' => Icons.place_outlined,
    'ITEM_RETURNED' => Icons.check_circle_outline_rounded,
    'NOT_MY_ITEM' => Icons.undo_rounded,
    _ => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.read ? Colors.white : const Color(0xFFF0FDF8),
          borderRadius: BorderRadius.circular(16),
          border: item.read
              ? null
              : Border.all(color: carShareGreen.withValues(alpha: 0.35)),
          boxShadow: const [carShareCardShadow],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: carShareGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon(item.type), color: carShareGreen, size: 22),
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
                            fontWeight: item.read
                                ? FontWeight.w700
                                : FontWeight.w800,
                            fontSize: 15,
                            color: carShareText,
                          ),
                        ),
                      ),
                      if (!item.read)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 5, left: 8),
                          decoration: const BoxDecoration(
                            color: carShareGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.body,
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
                        child: const Text(
                          'Lost & Found',
                          style: TextStyle(
                            color: carShareGreenDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('d MMM, HH:mm')
                            .format(item.createdAt.toLocal()),
                        style: const TextStyle(
                          fontSize: 12,
                          color: carShareMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: carShareMuted,
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
