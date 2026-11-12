import 'package:flutter/material.dart';

import '../models/user_trip_stats.dart';
import '../pages/main_shell.dart';
import '../services/reservation_service.dart';
import '../theme.dart';

/// The white card on the Profile screen with three figures: Trips, Rating and No-shows.
///
/// It is a bonus on a screen that must never break because of it: while the figures load it
/// shows a quiet placeholder of the same size, and if they cannot be loaded it draws nothing.
/// It loads again whenever the Profile tab is brought to the front.
class ProfileStatsCard extends StatefulWidget {
  const ProfileStatsCard({super.key});

  @override
  State<ProfileStatsCard> createState() => _ProfileStatsCardState();
}

class _ProfileStatsCardState extends State<ProfileStatsCard> {
  /// The FutureBuilder below shows whatever this future gives; a new future reloads the card.
  late Future<UserTripStats> _stats = ReservationService.instance.myStats();

  @override
  void initState() {
    super.initState();
    carShareShellTab.addListener(_onShellTab);
  }

  @override
  void dispose() {
    carShareShellTab.removeListener(_onShellTab);
    super.dispose();
  }

  /// The shell keeps Profile alive behind the other tabs, so the numbers would otherwise be
  /// those of the moment the app opened. Tab 3 is Profile.
  void _onShellTab() {
    if (carShareShellTab.value != 3 || !mounted) return;
    setState(() {
      _stats = ReservationService.instance.myStats();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UserTripStats>(
    future: _stats,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const SizedBox.shrink();
      final stats = snapshot.data;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(carShareCardRadius),
            boxShadow: const [carShareCardShadow],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _Figure(
                  label: 'Trips',
                  value: stats == null ? null : Text('${stats.totalTrips}'),
                ),
                const VerticalDivider(
                  width: 1,
                  indent: 4,
                  endIndent: 4,
                  color: carShareBorder,
                ),
                _Figure(
                  label: 'Rating',
                  value: stats == null ? null : _ratingValue(stats.rating),
                ),
                const VerticalDivider(
                  width: 1,
                  indent: 4,
                  endIndent: 4,
                  color: carShareBorder,
                ),
                _Figure(
                  label: 'No-shows',
                  value: stats == null ? null : Text('${stats.noShows}'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// "4.8 ★", or a dash when nobody has rated this user yet.
  Widget _ratingValue(double? rating) {
    if (rating == null) return const Text('—');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(rating.toStringAsFixed(1)),
        const SizedBox(width: 4),
        const Icon(Icons.star_rounded, size: 20, color: carShareWarning),
      ],
    );
  }
}

/// One column of the card: a big figure over a muted label. A null [value] is the loading
/// placeholder, a short grey bar where the figure will be.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final Widget? value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 30,
          child: Center(
            child: value == null
                ? Container(
                    width: 34,
                    height: 16,
                    decoration: BoxDecoration(
                      color: carShareBorder,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )
                : DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: carShareText,
                    ),
                    child: value!,
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 13, color: carShareMuted)),
      ],
    ),
  );
}
