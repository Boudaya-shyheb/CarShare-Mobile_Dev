import 'package:flutter/material.dart';

import '../../models/reservation.dart';
import '../../models/trip.dart';
import '../../models/user_profile.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/trip_formats.dart';
import '../main_shell.dart';
import 'live_driver_page.dart';
import 'live_passenger_page.dart';

/// The Live tab: finds the one trip this user is currently on, and hands it to the right view.
///
/// A driver follows their own trip from `DRIVER_EN_ROUTE` to `COMPLETED`; a passenger follows
/// the trip of a `CONFIRMED` reservation once the driver sets off. A trip that finished in the
/// last hour still opens, so the arrival screen does not vanish the moment it completes.
class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.user});

  final UserProfile user;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  /// How long a finished trip keeps its place in this tab.
  static const _keepFinishedFor = Duration(hours: 1);

  late Future<_ActiveTrip?> _active = _find();

  bool get _isDriver => widget.user.role == 'driver';

  @override
  void initState() {
    super.initState();
    // "Track live" on a My trips card names the trip to open before switching tab.
    carShareLiveTripId.addListener(_onRequestedTripChanged);
  }

  @override
  void dispose() {
    carShareLiveTripId.removeListener(_onRequestedTripChanged);
    super.dispose();
  }

  void _onRequestedTripChanged() {
    if (mounted) _reload();
  }

  void _reload() => setState(() {
    _active = _find();
  });

  Future<_ActiveTrip?> _find() async {
    final wanted = carShareLiveTripId.value;
    return _isDriver ? _findForDriver(wanted) : _findForPassenger(wanted);
  }

  Future<_ActiveTrip?> _findForDriver(String? wanted) async {
    final upcoming = await ReservationService.instance.myTrips(
      scope: 'upcoming',
    );
    final tracking = upcoming
        .where((trip) => tripIsTrackable(trip.status))
        .toList(growable: false);
    final chosen = _preferred(tracking, wanted, (trip) => trip.id);
    if (chosen != null) return _ActiveTrip(chosen.id, chosen);

    // Nothing moving: show a trip that finished a moment ago so its arrival screen stays up.
    final past = await ReservationService.instance.myTrips(scope: 'past');
    final recent = past
        .where((trip) => _justFinished(trip.departureTime))
        .toList(growable: false);
    final finished = _preferred(recent, wanted, (trip) => trip.id);
    return finished == null ? null : _ActiveTrip(finished.id, finished);
  }

  Future<_ActiveTrip?> _findForPassenger(String? wanted) async {
    final upcoming = await ReservationService.instance.myReservations(
      scope: 'upcoming',
    );
    final tracking = upcoming
        .where(
          (reservation) =>
              reservation.isConfirmed &&
              tripIsTrackable(reservation.trip.tripStatus),
        )
        .toList(growable: false);
    final chosen = _preferred(tracking, wanted, (r) => r.trip.tripId);
    if (chosen != null) {
      return _ActiveTrip(chosen.trip.tripId, null, reservation: chosen);
    }

    final past = await ReservationService.instance.myReservations(
      scope: 'past',
    );
    final recent = past
        .where((r) => _justFinished(r.trip.departureTime))
        .toList(growable: false);
    final finished = _preferred(recent, wanted, (r) => r.trip.tripId);
    return finished == null
        ? null
        : _ActiveTrip(finished.trip.tripId, null, reservation: finished);
  }

  /// The trip the user asked for, when it is in the list; otherwise the first one.
  T? _preferred<T>(List<T> rows, String? wanted, String Function(T) idOf) {
    if (rows.isEmpty) return null;
    if (wanted != null) {
      for (final row in rows) {
        if (idOf(row) == wanted) return row;
      }
    }
    return rows.first;
  }

  bool _justFinished(DateTime departure) =>
      DateTime.now().difference(departure) <
      _keepFinishedFor + const Duration(hours: 4);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    body: FutureBuilder<_ActiveTrip?>(
      future: _active,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _Empty(
            icon: Icons.cloud_off,
            title: 'Could not check your trips',
            line: authErrorMessage(snapshot.error!),
            onRetry: _reload,
          );
        }
        final active = snapshot.data;
        if (active == null) {
          return _Empty(
            icon: Icons.navigation_outlined,
            title: 'Nothing to follow right now',
            line: _isDriver
                ? 'Start one of your trips and the map will follow you here.'
                : 'Once a driver sets off on a trip you have booked, you can '
                      'follow them here.',
            onRetry: _reload,
          );
        }
        return _isDriver
            ? LiveDriverPage(tripId: active.tripId, onFinished: _reload)
            : LivePassengerPage(
                tripId: active.tripId,
                reservation: active.reservation!,
                onFinished: _reload,
              );
      },
    ),
  );
}

/// What the tab resolved to: a trip id, plus whichever side's row it came from.
class _ActiveTrip {
  const _ActiveTrip(this.tripId, this.trip, {this.reservation});

  final String tripId;
  final Trip? trip;
  final Reservation? reservation;
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.line,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 86,
            height: 86,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: carShareTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: carShareGreen),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            line,
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
          ),
        ],
      ),
    ),
  );
}
