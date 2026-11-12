import 'package:flutter/material.dart';

import '../models/admin_trip.dart';
import '../models/reservation.dart';
import '../models/trip.dart';
import '../models/trip_event.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/form_field.dart';
import '../widgets/route_title.dart';
import '../widgets/status_chip.dart';
import '../widgets/trip_formats.dart';

/// One trip as an admin sees it: the facts, who booked, what happened, and a Cancel button
/// while the rules still allow cancelling.
class AdminTripDetailsPage extends StatefulWidget {
  const AdminTripDetailsPage({super.key, required this.tripId});

  final String tripId;

  @override
  State<AdminTripDetailsPage> createState() => _AdminTripDetailsPageState();
}

class _AdminTripDetailsPageState extends State<AdminTripDetailsPage> {
  /// The FutureBuilder below shows whatever this future gives; a new future reloads the page.
  late Future<AdminTripDetail> _detail = AdminService.instance.tripDetails(
    widget.tripId,
  );
  bool _cancelling = false;

  void _reload() {
    setState(() {
      _detail = AdminService.instance.tripDetails(widget.tripId);
    });
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelDialog(),
    );
    if (reason == null || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await AdminService.instance.cancelTrip(widget.tripId, reason);
      if (!mounted) return;
      _say('Trip cancelled.');
      _reload();
    } catch (error) {
      if (mounted) _say(authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(title: const Text('Trip details')),
    body: FutureBuilder<AdminTripDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EmptyState(
                icon: Icons.cloud_off,
                title: 'Could not load this trip',
                line: authErrorMessage(snapshot.error!),
              ),
              FilledButton(onPressed: _reload, child: const Text('Retry')),
            ],
          );
        }
        return _content(snapshot.data!);
      },
    ),
  );

  Widget _content(AdminTripDetail detail) {
    final trip = detail.trip;
    // Every block of the page is one item, so the page is a ListView.builder.
    final items = <Widget>[
      _InfoCard(trip: trip),
      const SizedBox(height: 18),
      _SectionTitle('Passengers (${detail.reservations.length})'),
      if (detail.reservations.isEmpty)
        const _EmptyLine('Nobody has booked this trip.')
      else
        for (final passenger in detail.reservations)
          _PassengerRow(passenger: passenger),
      const SizedBox(height: 18),
      const _SectionTitle('Timeline'),
      if (detail.events.isEmpty)
        const _EmptyLine('Nothing has happened yet.')
      else
        for (final event in detail.events)
          _EventRow(event: event, who: _actorName(detail, event)),
      if (_canCancel(trip)) ...[
        const SizedBox(height: 22),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: carShareDanger,
            side: const BorderSide(color: carShareDanger),
            minimumSize: const Size.fromHeight(carShareButtonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(carShareButtonRadius),
            ),
          ),
          onPressed: _cancelling ? null : _cancel,
          icon: _cancelling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cancel_outlined),
          label: const Text(
            'Cancel this trip',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index],
    );
  }

  /// The API only lets a trip be cancelled before the driver has arrived.
  bool _canCancel(Trip trip) =>
      trip.status == 'SCHEDULED' || trip.status == 'DRIVER_EN_ROUTE';

  /// Who did it: the driver, a passenger by name, the system, or otherwise an admin.
  String _actorName(AdminTripDetail detail, TripEvent event) {
    final actor = event.actorId;
    if (actor == null) return 'System';
    if (actor == detail.trip.driverId) return 'Driver';
    for (final passenger in detail.reservations) {
      if (passenger.passengerId == actor) return passenger.passengerName;
    }
    return 'Admin';
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(carShareCardRadius),
      border: Border.all(color: carShareBorder),
    ),
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
        RouteTitle(
          origin: RouteTitle.shortName(trip.originLabel),
          destination: RouteTitle.shortName(trip.destinationLabel),
          fontSize: 19,
        ),
        const SizedBox(height: 10),
        _Fact(label: 'From', value: trip.originLabel),
        _Fact(label: 'To', value: trip.destinationLabel),
        _Fact(label: 'Driver', value: trip.driverName ?? 'Unknown'),
        _Fact(
          label: 'Seats',
          value:
              '${trip.seatsTotal - trip.seatsAvailable} taken of ${trip.seatsTotal}',
        ),
        _Fact(
          label: 'Price',
          value: '${formatPrice(trip.pricePerSeat)} per seat',
        ),
        if (trip.cancelReason != null)
          _Fact(label: 'Cancel reason', value: trip.cancelReason!),
        if (trip.notes != null && trip.notes!.isNotEmpty)
          _Fact(label: 'Notes', value: trip.notes!),
      ],
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: carShareMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: carShareText,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: carShareText,
      ),
    ),
  );
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: carShareMuted)),
  );
}

class _PassengerRow extends StatelessWidget {
  const _PassengerRow({required this.passenger});

  final PassengerView passenger;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: carShareBorder),
    ),
    child: Row(
      children: [
        InitialsAvatar(initials: initialsOf(passenger.passengerName)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                passenger.passengerName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: carShareText,
                ),
              ),
              Text(
                [
                  formatSeats(passenger.seats),
                  if (passenger.cancelReason != null) passenger.cancelReason!,
                ].join(' · '),
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
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.who});

  final TripEvent event;
  final String who;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            formatWhen(event.createdAt),
            style: const TextStyle(fontSize: 12, color: carShareMuted),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, right: 10),
          child: Icon(Icons.circle, size: 9, color: carShareGreen),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                prettyStatus(event.type),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: carShareText,
                ),
              ),
              Text(
                [who, if (event.detail != null) event.detail!].join(' · '),
                style: const TextStyle(fontSize: 13, color: carShareMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Asks why the trip is being cancelled. A Form with one validated field; pops the reason, or
/// null if the admin backs out.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Give a reason for the cancellation.';
    if (text.length > 300) return 'Keep it under 300 characters.';
    return null;
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Colors.white,
    title: const Text('Cancel this trip?'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Every reservation on it is closed and the seats are released. '
            'This cannot be undone.',
            style: TextStyle(color: carShareMuted),
          ),
          const SizedBox(height: 14),
          CarShareTextField(
            controller: _reason,
            label: 'Reason',
            icon: Icons.edit_note,
            validator: _validate,
            minLines: 2,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Keep trip'),
      ),
      TextButton(
        onPressed: _confirm,
        child: const Text(
          'Cancel trip',
          style: TextStyle(color: carShareDanger),
        ),
      ),
    ],
  );
}
