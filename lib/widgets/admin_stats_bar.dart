import 'package:flutter/material.dart';

import '../models/admin_stats.dart';
import '../services/admin_service.dart';
import '../theme.dart';

/// The counters row on top of the admin dashboard (`GET /api/admin/stats`): users, trips, trips
/// in progress, completed, cancelled, reservations and lost-and-found reports.
///
/// It reloads when [reloadKey] changes (the dashboard passes the selected tab, so the numbers
/// are fresh when the admin moves around) and from its refresh button.
class AdminStatsBar extends StatefulWidget {
  const AdminStatsBar({super.key, required this.reloadKey});

  final Object reloadKey;

  @override
  State<AdminStatsBar> createState() => _AdminStatsBarState();
}

class _AdminStatsBarState extends State<AdminStatsBar> {
  /// The FutureBuilder below shows whatever this future gives; a new future reloads the counters.
  late Future<AdminStats> _stats = AdminService.instance.stats();

  @override
  void didUpdateWidget(AdminStatsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) _reload();
  }

  void _reload() {
    setState(() {
      _stats = AdminService.instance.stats();
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 66,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: carShareBorder)),
    ),
    child: FutureBuilder<AdminStats>(
      future: _stats,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasError) {
          return Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.cloud_off, size: 18, color: carShareMuted),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Counters unavailable',
                  style: TextStyle(color: carShareMuted),
                ),
              ),
              TextButton(onPressed: _reload, child: const Text('Retry')),
            ],
          );
        }
        final stats = snapshot.data!;
        final counters = <(String, int)>[
          ('Users', stats.users),
          ('Trips', stats.tripsTotal),
          ('In progress', stats.tripsInProgress),
          ('Completed', stats.tripsCompleted),
          ('Cancelled', stats.tripsCancelled),
          ('Reservations', stats.reservations),
          ('Lost & found', stats.lostAndFoundReports),
        ];
        // No refresh button of its own: the counters reload when the admin changes tab, and
        // the AppBar refresh below reloads the list.
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          itemCount: counters.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) =>
              _Counter(label: counters[index].$1, value: counters[index].$2),
        );
      },
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: carShareTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: carShareText,
            height: 1.1,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: carShareMuted)),
      ],
    ),
  );
}
