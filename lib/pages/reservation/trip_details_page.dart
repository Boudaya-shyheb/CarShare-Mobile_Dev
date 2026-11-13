import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/reservation.dart';
import '../../models/trip.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/star_rating.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/trip_formats.dart';
import '../../widgets/trip_vehicle_card.dart';
import '../main_shell.dart';

/// Mockup 06 — one trip, its route on the map, and the booking form.
///
/// Pops `true` once a seat has been booked, so the list underneath knows to reload.
class TripDetailsPage extends StatefulWidget {
  const TripDetailsPage({
    super.key,
    required this.tripId,
    this.matchScore,
    this.seatsWanted = 1,
  });

  final String tripId;

  /// Carried over from the search result; the trip endpoint does not score the match.
  final int? matchScore;
  final int seatsWanted;

  @override
  State<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends State<TripDetailsPage> {
  late final Future<_TripWithRoute> _trip = _load();
  int _seats = 1;
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    _seats = widget.seatsWanted;
  }

  Future<_TripWithRoute> _load() async {
    final trip = await ReservationService.instance.trip(widget.tripId);
    if (mounted) {
      // Never offer more seats than are free; the search may be a few seconds stale.
      setState(() => _seats = _seats.clamp(1, trip.seatsAvailable.clamp(1, 8)));
    }

    // The driver's own polyline is the real route. Only when the trip was published without
    // one is OSRM asked, and a failure there costs the line on the map and nothing else.
    var points = GeoService.instance.decodePolyline(trip.routePolyline);
    if (points.isEmpty && trip.hasCoordinates) {
      try {
        final route = await GeoService.instance.route(
          originLat: trip.originLat!,
          originLng: trip.originLng!,
          destinationLat: trip.destinationLat!,
          destinationLng: trip.destinationLng!,
        );
        if (route != null) {
          points = GeoService.instance.decodePolyline(route.polyline);
        }
      } on ApiException {
        points = const [];
      }
    }

    // Does this passenger already hold a seat? Then the screen shows that instead of "Book".
    // The driver is never a passenger on their own trip. A failed lookup only costs the
    // reservation panel: the server still refuses a double booking.
    final userId = AuthService.instance.currentUser.value?.id;
    final isOwn = userId != null && trip.driverId == userId;
    Reservation? mine;
    if (userId != null && !isOwn) {
      try {
        for (final reservation in await ReservationService.instance.myReservations()) {
          final holdsOrHeld =
              reservation.isActive ||
              reservation.status == 'COMPLETED' ||
              reservation.status == 'NO_SHOW';
          if (reservation.trip.tripId == trip.id && holdsOrHeld) {
            mine = reservation;
            break;
          }
        }
      } on ApiException {
        mine = null;
      }
    }
    return _TripWithRoute(
      trip,
      points.map((p) => LatLng(p[0], p[1])).toList(growable: false),
      reservation: mine,
      isOwn: isOwn,
    );
  }

  /// The API's codes, in words a passenger can act on.
  String _bookingMessage(Object error) {
    if (error is! ApiException) return authErrorMessage(error);
    return switch (error.code) {
      'own_trip' => 'This is your own trip — you cannot book a seat on it.',
      'overlapping_reservation' =>
        'You already have a reservation on another trip at this time.',
      'seats_unavailable' =>
        'Somebody took those seats first. Try fewer seats, or another trip.',
      'account_restricted' =>
        'Your account cannot book trips at the moment. Check your profile.',
      'trip_not_bookable' => 'This trip is no longer taking reservations — it has left or been cancelled.',
      _ => authErrorMessage(error),
    };
  }

  Future<void> _book(Trip trip) async {
    setState(() => _booking = true);
    try {
      final reservation = await ReservationService.instance.bookSeat(
        trip.id,
        _seats,
      );
      if (!mounted) return;
      final confirmed = reservation.status == 'CONFIRMED';
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: confirmed ? carShareSuccess : carShareWarning,
          content: Text(
            confirmed
                ? 'Seat booked. ${trip.driverName ?? 'Your driver'} will pick '
                      'you up at ${formatClock(trip.departureTime)}.'
                : 'Request sent — waiting for the driver.',
          ),
        ),
      );
      // Either way the reservation now lives in My trips, so that is where to land: switch
      // the shell to that tab and drop the pushed pages, details and results both, that are
      // sitting on top of it. Popping only this page would leave the results list in view.
      carShareShellTab.value = 1;
      navigator.popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_bookingMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    body: FutureBuilder<_TripWithRoute>(
      future: _trip,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: carShareText),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        authErrorMessage(snapshot.error!),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: carShareMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return _buildTrip(snapshot.data!);
      },
    ),
  );

  Widget _buildTrip(_TripWithRoute loaded) {
    final mapHeight = MediaQuery.of(context).size.height * 0.40;
    // SizedBox.expand matters: a Stack takes its size from its non-positioned children, and
    // the tallest of those is the map. Without it the stack is only as tall as the map, so
    // the sheet below gets 28 pixels to lay out in and renders empty.
    return SizedBox.expand(
      child: Stack(
        children: [
          SizedBox(
            height: mapHeight,
            width: double.infinity,
            child: _buildMap(loaded),
          ),
          Positioned.fill(top: mapHeight - 28, child: _buildSheet(loaded)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: carShareText),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(_TripWithRoute loaded) {
    final trip = loaded.trip;
    if (!trip.hasCoordinates) {
      return Container(
        color: carShareBorder,
        alignment: Alignment.center,
        child: const Text(
          'No route to show for this trip.',
          style: TextStyle(color: carShareMuted),
        ),
      );
    }
    final pickup = LatLng(trip.originLat!, trip.originLng!);
    final dropoff = LatLng(trip.destinationLat!, trip.destinationLng!);
    final bounds = LatLngBounds.fromPoints([pickup, dropoff, ...loaded.route]);
    return FlutterMap(
      options: MapOptions(
        // Fitting the whole route is what makes the screen readable; a fixed zoom would cut
        // off anything longer than a few kilometres.
        initialCameraFit: CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(48, 60, 48, 70),
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.carshare.app',
        ),
        if (loaded.route.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: loaded.route,
                strokeWidth: 5,
                color: carShareGreen,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: pickup,
              width: 26,
              height: 26,
              child: const _EndDot(square: false),
            ),
            Marker(
              point: dropoff,
              width: 26,
              height: 26,
              child: const _EndDot(square: true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSheet(_TripWithRoute loaded) {
    final trip = loaded.trip;
    final reservation = loaded.reservation;
    final maxSeats = trip.seatsAvailable.clamp(1, 8);
    final departed = !trip.departureTime.isAfter(DateTime.now());
    // Book only when it can work: not the driver's own trip, no seat held already, still
    // scheduled, not yet departed, and a seat left. Otherwise the reason is shown instead.
    final bookable =
        trip.status == 'SCHEDULED' &&
        trip.seatsAvailable > 0 &&
        !departed &&
        !loaded.isOwn &&
        reservation == null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDriverRow(trip),
                        const SizedBox(height: 16),
                        _buildVehicleRow(trip),
                        const SizedBox(height: 18),
                        _buildTimeline(trip),
                        const SizedBox(height: 18),
                        _buildStats(trip),
                        if (trip.notes != null && trip.notes!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            trip.notes!,
                            style: const TextStyle(
                              color: carShareMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Pinned above the button rather than left at the end of the scroll view,
                // where the round +/- buttons are clipped by the viewport edge on first paint.
                if (bookable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: _buildStepper(maxSeats),
                  ),
                if (!bookable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _buildWhyNotBookable(
                      trip: trip,
                      reservation: reservation,
                      isOwn: loaded.isOwn,
                      departed: departed,
                    ),
                  ),
                if (bookable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: carShareButtonHeight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            carShareButtonRadius,
                          ),
                        ),
                      ),
                      onPressed: !bookable || _booking
                          ? null
                          : () => _book(trip),
                      child: _booking
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              bookable
                                  ? 'Book ${formatSeats(_seats)} · '
                                        '${formatPrice(trip.pricePerSeat * _seats)}'
                                  : 'Not taking reservations',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDriverRow(Trip trip) {
    final name = trip.driverName ?? 'Driver';
    return Row(
      children: [
        InitialsAvatar(initials: initialsOf(name), size: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
              const SizedBox(height: 2),
              RatingLine(
                average: trip.driverRating,
                count: trip.driverRatingCount,
              ),
            ],
          ),
        ),
        if (widget.matchScore != null)
          StatusChip(
            label: '${widget.matchScore}% match',
            colour: carShareGreen,
          ),
      ],
    );
  }

  Widget _buildVehicleRow(Trip trip) => TripVehicleCard(
    tripId: trip.id,
    trailing: trip.instantBooking
        ? const StatusChip(label: 'Instant', colour: carShareGreen)
        : null,
  );

  /// What replaces the Book button when booking is not possible: the passenger's own
  /// reservation (with the pickup code once confirmed), or the plain reason.
  Widget _buildWhyNotBookable({
    required Trip trip,
    required Reservation? reservation,
    required bool isOwn,
    required bool departed,
  }) {
    if (reservation != null) {
      final label = reservationStatusLabel(reservation.status);
      final colour = reservationStatusColour(reservation.status);
      final code = reservation.pickupCode;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colour.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your reservation · ${formatSeats(reservation.seats)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: carShareText,
                    ),
                  ),
                ),
                StatusChip(label: label, colour: colour),
              ],
            ),
            if (reservation.status == 'PENDING') ...[
              const SizedBox(height: 6),
              const Text(
                'Waiting for the driver to answer your request.',
                style: TextStyle(color: carShareMuted),
              ),
            ],
            if (reservation.isConfirmed && code != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Show this code to the driver at pickup',
                style: TextStyle(color: carShareMuted),
              ),
              const SizedBox(height: 4),
              Text(
                code,
                style: const TextStyle(
                  fontSize: 28,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w800,
                  color: carShareGreen,
                ),
              ),
            ],
          ],
        ),
      );
    }
    final (IconData icon, String text) = isOwn
        ? (Icons.drive_eta_outlined, 'This is your own trip. Manage it from My trips.')
        : trip.status == 'CANCELLED'
        ? (Icons.cancel_outlined, 'This trip was cancelled.')
        : departed
        ? (Icons.schedule, 'This trip has already left.')
        : trip.seatsAvailable <= 0
        ? (Icons.event_seat_outlined, 'No seats left on this trip.')
        : (Icons.info_outline, 'This trip is not taking reservations.');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: carShareBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: carShareMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: carShareText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(Trip trip) {
    final arrival = trip.durationS == null
        ? null
        : trip.departureTime.add(Duration(seconds: trip.durationS!));
    return Column(
      children: [
        _TimelineRow(
          square: false,
          time: formatClock(trip.departureTime),
          caption: 'Pickup',
          label: trip.originLabel,
          showBar: true,
        ),
        _TimelineRow(
          square: true,
          time: arrival == null ? '—' : formatClock(arrival),
          caption: 'Drop-off',
          label: trip.destinationLabel,
          showBar: false,
        ),
      ],
    );
  }

  Widget _buildStats(Trip trip) => Row(
    children: [
      _Stat(
        value: '${trip.seatsAvailable} / ${trip.seatsTotal}',
        caption: 'Seats left',
      ),
      const SizedBox(width: 10),
      _Stat(value: formatPrice(trip.pricePerSeat), caption: 'Per seat'),
      const SizedBox(width: 10),
      _Stat(value: formatDuration(trip.durationS), caption: 'Duration'),
    ],
  );

  Widget _buildStepper(int maxSeats) => Row(
    children: [
      const Expanded(
        child: Text(
          'Seats to book',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: carShareText,
          ),
        ),
      ),
      _StepperButton(
        icon: Icons.remove,
        filled: false,
        onTap: _seats <= 1 ? null : () => setState(() => _seats--),
      ),
      SizedBox(
        width: 48,
        child: Text(
          '$_seats',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: carShareText,
          ),
        ),
      ),
      _StepperButton(
        icon: Icons.add,
        filled: true,
        onTap: _seats >= maxSeats ? null : () => setState(() => _seats++),
      ),
    ],
  );
}

/// A trip and the route to draw for it, resolved together so the screen builds once.
class _TripWithRoute {
  const _TripWithRoute(
    this.trip,
    this.route, {
    this.reservation,
    this.isOwn = false,
  });
  final Trip trip;
  final List<LatLng> route;

  /// The signed-in passenger's own reservation on this trip, when they hold or held a seat.
  final Reservation? reservation;

  /// True when the signed-in user is this trip's driver.
  final bool isOwn;
}

class _EndDot extends StatelessWidget {
  const _EndDot({required this.square});

  final bool square;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: square ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: square ? BorderRadius.circular(7) : null,
      boxShadow: const [carShareCardShadow],
    ),
    padding: const EdgeInsets.all(5),
    child: Container(
      decoration: BoxDecoration(
        color: square ? const Color(0xFF065F46) : carShareSuccess,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(4) : null,
      ),
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.square,
    required this.time,
    required this.caption,
    required this.label,
    required this.showBar,
  });

  final bool square;
  final String time;
  final String caption;
  final String label;
  final bool showBar;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          SizedBox(width: 26, height: 26, child: _EndDot(square: square)),
          if (showBar) Container(width: 2, height: 32, color: carShareBorder),
        ],
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(bottom: showBar ? 14 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$time · $caption',
                style: const TextStyle(fontSize: 13, color: carShareMuted),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: carShareText,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.caption});

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: carShareBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(fontSize: 12, color: carShareMuted),
          ),
        ],
      ),
    ),
  );
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: filled && enabled
          ? carShareGreen
          : (enabled ? carShareBackground : carShareBackground),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 22,
            color: filled && enabled
                ? Colors.white
                : (enabled ? carShareText : carShareBorder),
          ),
        ),
      ),
    );
  }
}
