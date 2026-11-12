import 'package:flutter/material.dart';

import '../../models/support_notification.dart';
import '../../services/support_service.dart';
import '../../theme.dart';

class SupportNotificationsPage extends StatefulWidget {
  const SupportNotificationsPage({super.key});

  @override
  State<SupportNotificationsPage> createState() =>
      _SupportNotificationsPageState();
}

class _SupportNotificationsPageState extends State<SupportNotificationsPage> {
  late Future<List<SupportNotificationItem>> _notifications = _load();

  Future<List<SupportNotificationItem>> _load() =>
      SupportService.instance.notifications();

  void _refresh() {
    final notifications = _load();
    setState(() {
      _notifications = notifications;
    });
  }

  Future<void> _markRead(SupportNotificationItem item) async {
    if (!item.read) {
      await SupportService.instance.markNotificationRead(item.id);
      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      title: const Text('Support notifications'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<SupportNotificationItem>>(
      future: _notifications,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton(
              onPressed: _refresh,
              child: Text('Try again: ${snapshot.error}'),
            ),
          );
        }
        final rows = snapshot.data ?? const <SupportNotificationItem>[];
        if (rows.isEmpty) {
          return const Center(child: Text('No support notifications yet.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = rows[index];
            return Card(
              color: item.read ? Colors.white : carShareTint,
              child: ListTile(
                onTap: () => _markRead(item),
                leading: Icon(
                  item.read
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_active_rounded,
                  color: supportGreen,
                ),
                title: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: item.read ? FontWeight.w600 : FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  '${item.ticketReference}\n${item.message}\n${_date(item.createdAt)}',
                ),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    ),
  );

  String _date(DateTime? value) {
    if (value == null) return 'Recently';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }
}
