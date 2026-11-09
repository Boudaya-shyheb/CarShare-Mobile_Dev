import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/live_view.dart';
import '../../models/reservation.dart';
import '../../models/trip.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/live_widgets.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/trip_formats.dart';
import '../main_shell.dart';
import 'trip_completed_page.dart';

/// Mockups 08, 09 and 10 — what the passenger sees while their driver is on the way.
class LivePassengerPage extends StatefulWidget {
  const LivePassengerPage({
    super.key,
    required this.tripId,
    required this.reservation,
    required this.onFinished,
  });

  final String tripId;
  final Reservation reservation;

  /// Asks the Live tab to look for the next trip, once this one is done with.
  final VoidCallback onFinished;

  @override
  State<LivePassengerPage> createState() => _LivePassengerPageState();
}

class _LivePassengerPageState extends State<LivePassengerPage>
    with WidgetsBindingObserver {
  /// The live endpoint is built to be polled at this rate; there are no websockets.
  static const _pollEvery = Duration(seconds: 5);

  Timer? _poll;
  Trip? _trip;
  List<LatLng> _route = const [];
  LiveView? _live;
  String? _error;

  /// Where the car was drawn last, so each new fix animates from it instead of jumping.
  LatLng? _carFrom;
  LatLng? _carTo;

  /// "I'm OK" hides the deviation card for this stretch only; a new deviation shows it again.
  bool _deviationDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No point polling a screen nobody is looking at — and it would keep the radio awake.
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> _load() async {
    try {
      final trip = await ReservationService.instance.trip(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _route = GeoService.instance
            .decodePolyline(trip.routePolyline)
            .map((p) => LatLng(p[0], p[1]))
            .toList(growable: false);
      });
      await _tick();
      _startPolling();
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    }
  }

  void _startPolling() {
    _poll?.cancel();
    if (_live?.isFinished ?? false) return;
    _poll = Timer.periodic(_pollEvery, (_) => _tick());
  }

  Future<void> _tick() async {
    try {
      final view = await ReservationService.instance.liveView(widget.tripId);
      if (!mounted) return;
      setState(() {
        _error = null;
        if (!view.deviating) _deviationDismissed = false;
        if (view.hasPosition) {
          _carFrom = _carTo ?? LatLng(view.lastLat!, view.lastLng!);
          _carTo = LatLng(view.lastLat!, view.lastLng!);
        }
        _live = view;
      });
      // Nothing more will change once the trip is over.
      if (view.isFinished) {
        _poll?.cancel();
        _poll = null;
      }
    } catch (error) {
      // A failed poll is usually a blip; keep the last view on screen and say so quietly.
      if (mounted) setState(() => _error = authErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    if (trip == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : _ErrorBody(message: _error!, onRetry: _load);
    }
    final live = _live;
    if (live != null && live.tripStatus == 'COMPLETED') {
      return TripCompletedView(
        trip: trip,
        arrivedAt: live.lastPositionAt,
        onDone: () {
          carShareLiveTripId.value = null;
          carShareShellTab.value = 0;
          widget.onFinished();
        },
      );
    }
    if (live != null && live.tripStatus == 'CANCELLED') {
      return _ErrorBody(
        message: 'This trip was cancelled.',
        onRetry: widget.onFinished,
        retryLabel: 'Back',
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: _buildMap(trip)),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: LiveStatusPill(
                  label: live == null
                      ? 'Connecting…'
                      : prettyStatus(live.tripStatus),
                  colour: live != null && live.deviating
                      ? carShareWarning
                      : carShareSuccess,
                ),
              ),
              if (live != null && live.deviating && !_deviationDismissed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DeviationCard(
                    onDismiss: () => setState(() => _deviationDismissed = true),
                  ),
                ),
              const Spacer(),
              _buildSheet(trip, live),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMap(Trip trip) {
    if (!trip.hasCoordinates) {
      return Container(color: carShareBorder);
    }
    final from = _carFrom;
    final to = _carTo;
    // Each poll moves the marker smoothly from where it was to the new fix.
    return TweenAnimationBuilder<double>(
      key: ValueKey(to),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      builder: (context, t, _) {
        LatLng? car;
        if (to != null) {
          car = from == null
              ? to
              : LatLng(
                  from.latitude + (to.latitude - from.latitude) * t,
                  from.longitude + (to.longitude - from.longitude) * t,
                );
        }
        final pickup = LatLng(trip.originLat!, trip.originLng!);
        final dropoff = LatLng(trip.destinationLat!, trip.destinationLng!);
        return LiveMap(
          route: _route,
          pickup: pickup,
          dropoff: dropoff,
          car: car,
          target: (_live?.isHeadingToPickup ?? true) ? pickup : dropoff,
        );
      },
    );
  }

  Widget _buildSheet(Trip trip, LiveView? live) {
    final arrived = live?.tripStatus == 'DRIVER_ARRIVED';
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [carShareCardShadow],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: carShareBorder,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TripStatusStepper(
                    tripStatus: live?.tripStatus ?? trip.status,
                  ),
                  const SizedBox(height: 20),
                  if (arrived)
                    _CheckInCard(
                      driverName: trip.driverName ?? 'Your driver',
                      code: widget.reservation.pickupCode,
                      checkedIn: live?.checkedIn ?? false,
                    )
                  else
                    _buildEta(live),
                  const SizedBox(height: 16),
                  _buildDriverRow(trip),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: carShareMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEta(LiveView? live) {
    if (live == null || live.etaSeconds == null) {
      return const Text(
        'Waiting for the driver to send a position…',
        style: TextStyle(fontSize: 15, color: carShareMuted),
      );
    }
    final minutes = (live.etaSeconds! / 60).ceil();
    final arriving = DateTime.now().add(Duration(seconds: live.etaSeconds!));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$minutes min',
          style: const TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            color: carShareGreen,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                live.isHeadingToPickup
                    ? 'Picking you up at ${formatClock(arriving)}'
                    : 'Arriving at ${formatClock(arriving)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: carShareText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                live.distanceToTargetM == null
                    ? 'live ETA'
                    : '${formatDistance(live.distanceToTargetM!)} away · live ETA',
                style: const TextStyle(fontSize: 13, color: carShareMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDriverRow(Trip trip) {
    final name = trip.driverName ?? 'Your driver';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: carShareBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          InitialsAvatar(initials: initialsOf(name), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: carShareText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pickup · ${trip.originLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: carShareMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mockup 09 — the code the driver asks for, as a QR and as four digits.
class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.driverName,
    required this.code,
    required this.checkedIn,
  });

  final String driverName;
  final String? code;
  final bool checkedIn;

  @override
  Widget build(BuildContext context) {
    if (checkedIn) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: carShareSuccess),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pickup confirmed. Enjoy the ride with $driverName.',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: carShareText,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$driverName has arrived',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: carShareText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Show this to your driver, or let them scan the QR.',
          style: TextStyle(fontSize: 14, color: carShareMuted, height: 1.3),
        ),
        const SizedBox(height: 14),
        if (code == null)
          const Text(
            'Your pickup code is on the reservation in My trips.',
            style: TextStyle(color: carShareMuted),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: carShareBackground,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: code!,
                    size: 150,
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: carShareText,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: carShareText,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final digit in code!.split(''))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Container(
                          width: 54,
                          height: 62,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: carShareGreen),
                          ),
                          child: Text(
                            digit,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: carShareGreen,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    ),
  );
}
