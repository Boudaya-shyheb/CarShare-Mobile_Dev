import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/lost_and_found_notification.dart';
import '../services/auth_service.dart';
import '../services/lost_and_found_notification_service.dart';
import '../services/support_service.dart';
import '../theme.dart';
import '../widgets/resume_refresh.dart';
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
      appBar: AppBar(
        backgroundColor: carShareBackground,
        surfaceTintColor: carShareBackground,
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w800, color: carShareText),
        ),
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
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text(
                    authErrorMessage(snapshot.error!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: carShareMuted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refreshAll,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ],
        );
      }
      final rows = snapshot.data ?? const <LostAndFoundNotification>[];
      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: rows.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 90),
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 44,
                    color: carShareMuted,
                  ),
                  SizedBox(height: 10),
                  Center(
                    child: Text(
                      'No Lost & Found updates yet',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: carShareText,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'You will hear about matches, meetings and returns here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: carShareMuted),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _NotificationCard(
                  item: rows[index],
                  onTap: () => _open(rows[index]),
                ),
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
          border: Border.all(
            color: item.read
                ? carShareBorder
                : carShareGreen.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: carShareTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon(item.type), color: carShareGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: item.read
                                ? FontWeight.w600
                                : FontWeight.w800,
                            color: carShareText,
                          ),
                        ),
                      ),
                      if (!item.read)
                        const Icon(
                          Icons.circle,
                          size: 10,
                          color: carShareGreen,
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    style: const TextStyle(color: carShareMuted, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateFormat('d MMM, HH:mm').format(item.createdAt.toLocal()),
                    style: const TextStyle(fontSize: 12, color: carShareMuted),
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
