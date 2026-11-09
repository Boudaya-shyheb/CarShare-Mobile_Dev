import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/live_view.dart';
import '../../models/reservation.dart';
import '../../models/trip.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../services/reservation_service.dart';
import '../../services/tracking_service.dart';
import '../../theme.dart';
import '../../widgets/live_widgets.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/trip_formats.dart';
import '../main_shell.dart';
import 'check_in_dialog.dart';
import 'trip_completed_page.dart';

/// The driver's side of the live screen: the same map and stepper, plus the controls only the
/// driver has — checking passengers in, marking a no-show, and starting the ride.
///
/// While this page is open the phone streams its position to the API and the screen is kept
/// awake. Tracking stops the moment the page is left: there is no background service.
class LiveDriverPage extends StatefulWidget {
  const LiveDriverPage({
    super.key,
    required this.tripId,
    required this.onFinished,
  });

  final String tripId;
  final VoidCallback onFinished;

  @override
  State<LiveDriverPage> createState() => _LiveDriverPageState();
}

class _LiveDriverPageState extends State<LiveDriverPage>
    with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 5);

  /// The API refuses a no-show until the driver has waited this long after arriving.
  static const _noShowAfter = Duration(minutes: 5);

  Timer? _poll;
  Timer? _countdown;
  StreamSubscription<LiveView>? _sentViews;
  StreamSubscription<String>? _problems;

  Trip? _trip;
  List<LatLng> _route = const [];
  LiveView? _live;
  List<PassengerView> _passengers = const [];
  DateTime? _arrivedAt;
  int _pending = 0;
  String? _error;
  bool _busy = false;
  bool _deviationDismissed = false;
  LatLng? _carFrom;
  LatLng? _carTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Positions the tracker just sent come back as a LiveView, so the screen updates without
    // waiting for its own poll.
    _sentViews = TrackingService.instance.views.listen(_applyView);
    _problems = TrackingService.instance.problems.listen((message) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    });
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _countdown?.cancel();
    _sentViews?.cancel();
    _problems?.cancel();
    TrackingService.instance.stop();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _startTrackingIfDriving();
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
      await _startTrackingIfDriving();
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    }
  }

  void _startPolling() {
    _poll?.cancel();
    if (_live?.isFinished ?? false) return;
    _poll = Timer.periodic(_pollEvery, (_) => _tick());
  }

  Future<void> _startTrackingIfDriving() async {
    final status = _live?.tripStatus ?? _trip?.status;
    if (status == null || !tripIsTrackable(status)) return;
    await TrackingService.instance.start(widget.tripId);
    await WakelockPlus.enable();
  }

  void _applyView(LiveView view) {
    if (!mounted) return;
    setState(() {
      if (!view.deviating) _deviationDismissed = false;
      if (view.hasPosition) {
        _carFrom = _carTo ?? LatLng(view.lastLat!, view.lastLng!);
        _carTo = LatLng(view.lastLat!, view.lastLng!);
      }
      _live = view;
    });
  }

  Future<void> _tick() async {
    try {
      final view = await ReservationService.instance.liveView(widget.tripId);
      final previous = _live?.tripStatus;
      if (!mounted) return;
      _applyView(view);
      setState(() => _error = null);

      // The passenger list and the arrival clock only matter once the driver is waiting.
      if (view.tripStatus == 'DRIVER_ARRIVED') {
        await _refreshPassengers();
        if (previous != 'DRIVER_ARRIVED') await _readArrivalTime();
        _startCountdown();
      }
      if (view.isFinished) {
        _poll?.cancel();
        _poll = null;
        _countdown?.cancel();
        await TrackingService.instance.stop();
        await WakelockPlus.disable();
      }
      final count = await TrackingService.instance.pendingCount(widget.tripId);
      if (mounted && count != _pending) setState(() => _pending = count);
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    }
  }

  Future<void> _refreshPassengers() async {
    final rows = await ReservationService.instance.tripReservations(
      widget.tripId,
    );
    if (mounted) {
      setState(
        () => _passengers = rows
            .where((p) => p.status == 'CONFIRMED' || p.status == 'NO_SHOW')
            .toList(growable: false),
      );
    }
  }

  /// The no-show window runs from the DRIVER_ARRIVED event, which the audit trail carries.
  Future<void> _readArrivalTime() async {
    try {
      final events = await ReservationService.instance.tripEvents(
        widget.tripId,
      );
      final arrivals = events
          .where((e) => e.type == 'DRIVER_ARRIVED')
          .toList(growable: false);
      if (arrivals.isNotEmpty && mounted) {
        setState(() => _arrivedAt = arrivals.last.createdAt);
      }
    } on ApiException {
      // Without it the no-show button just stays disabled; not worth an error on screen.
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Duration get _waitLeft {
    final arrived = _arrivedAt;
    if (arrived == null) return _noShowAfter;
    final left = _noShowAfter - DateTime.now().difference(arrived);
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _tick();
      await _refreshPassengers();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(PassengerView passenger) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => CheckInDialog(
        reservationId: passenger.reservationId,
        passengerName: passenger.passengerName,
      ),
    );
    if (done == true && mounted) {
      await _tick();
      await _refreshPassengers();
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
    if (!trip.hasCoordinates) return Container(color: carShareBorder);
    final from = _carFrom;
    final to = _carTo;
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
    final status = live?.tripStatus ?? trip.status;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [carShareCardShadow],
      ),
      child: SafeArea(
        top: false,
        // Align with heightFactor 1 hugs the content. A Center here would stretch to the
        // maxHeight above and leave a block of empty white above the handle.
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
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
                  TripStatusStepper(tripStatus: status),
                  const SizedBox(height: 18),
                  _buildTrackingNote(),
                  if (status == 'DRIVER_ARRIVED') ...[
                    const SizedBox(height: 18),
                    _buildPassengerList(),
                  ],
                  if (status == 'PICKED_UP') ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: carShareButtonHeight,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              carShareButtonRadius,
                            ),
                          ),
                        ),
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => ReservationService.instance
                                    .changeTripStatus(
                                      widget.tripId,
                                      'IN_PROGRESS',
                                    ),
                                'Ride started. Drive safely.',
                              ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text(
                          'Start ride',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
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

  Widget _buildTrackingNote() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: carShareBackground,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(
          _pending > 0 ? Icons.cloud_off : Icons.my_location,
          size: 20,
          color: _pending > 0 ? carShareWarning : carShareGreen,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _pending > 0
                ? '$_pending fixes saved offline — they will be sent when you '
                      'are back online.'
                : 'Sharing your position. Tracking only works while CarShare '
                      'is open on screen.',
            style: const TextStyle(fontSize: 12.5, color: carShareMuted),
          ),
        ),
      ],
    ),
  );

  Widget _buildPassengerList() {
    final waiting = _waitLeft;
    final canNoShow = waiting == Duration.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Passengers',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: carShareText,
          ),
        ),
        const SizedBox(height: 10),
        if (_passengers.isEmpty)
          const Text(
            'Nobody to check in on this trip.',
            style: TextStyle(color: carShareMuted),
          ),
        for (final passenger in _passengers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CarShareCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      InitialsAvatar(
                        initials: initialsOf(passenger.passengerName),
                        size: 40,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          passenger.passengerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: carShareText,
                          ),
                        ),
                      ),
                      StatusChip(
                        label: reservationStatusLabel(passenger.status),
                        colour: reservationStatusColour(passenger.status),
                      ),
                    ],
                  ),
                  if (passenger.status == 'CONFIRMED') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy || !canNoShow
                                ? null
                                : () => _run(
                                    () => ReservationService.instance
                                        .markNoShow(passenger.reservationId),
                                    '${passenger.passengerName} marked as a no-show.',
                                  ),
                            child: Text(
                              canNoShow
                                  ? 'No-show'
                                  : 'No-show in ${_mmss(waiting)}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : () => _checkIn(passenger),
                            child: const Text('Check in'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
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
