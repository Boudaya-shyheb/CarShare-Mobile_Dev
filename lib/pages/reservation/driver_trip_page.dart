import 'package:flutter/material.dart';

import '../../models/reservation.dart';
import '../../models/trip.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/trip_formats.dart';

/// One of the driver's own trips: who booked it, and the decisions only the driver can take.
///
/// Pops `true` when anything changed, so the list behind it reloads.
class DriverTripPage extends StatefulWidget {
  const DriverTripPage({super.key, required this.tripId});

  final String tripId;

  @override
  State<DriverTripPage> createState() => _DriverTripPageState();
}

class _DriverTripPageState extends State<DriverTripPage> {
  late Future<_DriverTrip> _data = _load();
  bool _changed = false;
  bool _busy = false;

  Future<_DriverTrip> _load() async {
    final trip = await ReservationService.instance.trip(widget.tripId);
    final passengers = await ReservationService.instance.tripReservations(
      widget.tripId,
    );
    return _DriverTrip(trip, passengers);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _data = future;
    });
    await future.catchError((_) => _DriverTrip.empty);
  }

  /// Runs an action, reports whatever the API says, and reloads on success.
  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTrip() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Cancel this trip?',
        note: 'Every reservation on it is closed and the seats are released.',
        confirmLabel: 'Cancel trip',
      ),
    );
    if (reason == null) return;
    await _run(
      () => ReservationService.instance.cancelTrip(widget.tripId, reason),
      'Trip cancelled.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: const Text(
        'Trip',
        style: TextStyle(fontWeight: FontWeight.w700, color: carShareText),
      ),
    ),
    // Everything here can change the list underneath, so the result travels back on pop.
    body: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: carShareGreen,
              child: FutureBuilder<_DriverTrip>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            authErrorMessage(snapshot.error!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: carShareMuted),
                          ),
                        ),
                      ],
                    );
                  }
                  return _buildBody(snapshot.data!);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildBody(_DriverTrip data) {
    final trip = data.trip;
    final active = data.passengers
        .where((p) => p.status == 'PENDING' || p.status == 'CONFIRMED')
        .toList(growable: false);
    final closed = data.passengers
        .where((p) => p.status != 'PENDING' && p.status != 'CONFIRMED')
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        CarShareCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusChip(
                    label: prettyStatus(trip.status),
                    colour: tripStatusColour(trip.status),
                  ),
                  const Spacer(),
                  Text(
                    formatWhen(trip.departureTime),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: carShareMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${trip.originLabel} → ${trip.destinationLabel}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${trip.seatsTotal - trip.seatsAvailable}/${trip.seatsTotal} '
                'seats booked · ${formatPrice(trip.pricePerSeat)} per seat',
                style: const TextStyle(fontSize: 13, color: carShareMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (trip.status == 'SCHEDULED') ...[
          SizedBox(
            width: double.infinity,
            height: carShareButtonHeight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(carShareButtonRadius),
                ),
              ),
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => ReservationService.instance.changeTripStatus(
                        widget.tripId,
                        'DRIVER_EN_ROUTE',
                      ),
                      'You are on your way. Passengers can follow you now.',
                    ),
              icon: const Icon(Icons.navigation_outlined),
              label: const Text(
                'Start trip',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (trip.status == 'SCHEDULED' || trip.status == 'DRIVER_EN_ROUTE')
          SizedBox(
            width: double.infinity,
            height: carShareButtonHeight,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: carShareDanger,
                side: const BorderSide(color: carShareDanger),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(carShareButtonRadius),
                ),
              ),
              onPressed: _busy ? null : _cancelTrip,
              child: const Text(
                'Cancel trip',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
        const SizedBox(height: 22),
        const Text(
          'Passengers',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: carShareText,
          ),
        ),
        const SizedBox(height: 10),
        if (data.passengers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nobody has booked a seat yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: carShareMuted),
            ),
          ),
        for (final passenger in [...active, ...closed])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PassengerCard(
              passenger: passenger,
              busy: _busy,
              onAccept: () => _run(
                () => ReservationService.instance.acceptReservation(
                  passenger.reservationId,
                ),
                '${passenger.passengerName} is confirmed.',
              ),
              onRefuse: () => _run(
                () => ReservationService.instance.refuseReservation(
                  passenger.reservationId,
                ),
                'Request refused.',
              ),
            ),
          ),
      ],
    );
  }
}

class _DriverTrip {
  const _DriverTrip(this.trip, this.passengers);
  final Trip trip;
  final List<PassengerView> passengers;

  static final empty = _DriverTrip(
    Trip(
      id: '',
      originLabel: '',
      destinationLabel: '',
      departureTime: DateTime.fromMillisecondsSinceEpoch(0),
      seatsTotal: 0,
      seatsAvailable: 0,
      pricePerSeat: 0,
      status: 'CANCELLED',
      instantBooking: false,
    ),
    const [],
  );
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({
    required this.passenger,
    required this.busy,
    required this.onAccept,
    required this.onRefuse,
  });

  final PassengerView passenger;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onRefuse;

  @override
  Widget build(BuildContext context) => CarShareCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InitialsAvatar(
              initials: initialsOf(passenger.passengerName),
              size: 42,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    passenger.passengerName,
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
                    formatSeats(passenger.seats),
                    style: const TextStyle(fontSize: 13, color: carShareMuted),
                  ),
                ],
              ),
            ),
            StatusChip(
              label: reservationStatusLabel(passenger.status),
              colour: reservationStatusColour(passenger.status),
            ),
          ],
        ),
        if (passenger.awaitsDecision) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onRefuse,
                  child: const Text('Refuse'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// Asks for the reason the cancel endpoints require.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.note,
    required this.confirmLabel,
  });

  final String title;
  final String note;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.note,
            style: const TextStyle(color: carShareMuted, height: 1.3),
          ),
          const SizedBox(height: 14),
          CarShareTextField(
            controller: _reason,
            label: 'Reason',
            icon: Icons.edit_outlined,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Please give a reason.';
              if (text.length > 200) return 'Keep it under 200 characters.';
              return null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Keep it'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}
