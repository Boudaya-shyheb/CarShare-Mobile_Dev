import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../models/trip.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/trip_formats.dart';
import 'place_search_page.dart';

/// The driver's publish form. No mockup — built from the same pieces as the search sheet.
///
/// Pops `true` once a trip has been published.
class PublishTripPage extends StatefulWidget {
  const PublishTripPage({super.key});

  @override
  State<PublishTripPage> createState() => _PublishTripPageState();
}

class _PublishTripPageState extends State<PublishTripPage> {
  final _formKey = GlobalKey<FormState>();
  final _price = TextEditingController(text: '5');
  final _notes = TextEditingController();

  Place? _from;
  Place? _to;
  DateTime _departure = DateTime.now().add(const Duration(hours: 1));
  int _seats = 3;
  bool _instantBooking = false;
  bool _saving = false;

  /// The route between the two places: drawn as a preview and sent with the trip.
  RouteInfo? _route;
  List<LatLng> _routePoints = const [];
  bool _routing = false;

  @override
  void dispose() {
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPlace({required bool isFrom}) async {
    final picked = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => PlaceSearchPage(
          title: isFrom ? 'Leaving from' : 'Going to',
          near: _from ?? _to,
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _loadRoute();
  }

  /// Asks OSRM for the route once both ends are known. A failure is not fatal: the trip can
  /// still be published without a polyline, it just will not be watched for deviation.
  Future<void> _loadRoute() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;
    setState(() => _routing = true);
    try {
      final route = await GeoService.instance.route(
        originLat: from.lat,
        originLng: from.lng,
        destinationLat: to.lat,
        destinationLng: to.lng,
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _routePoints = route == null
            ? const []
            : GeoService.instance
                  .decodePolyline(route.polyline)
                  .map((p) => LatLng(p[0], p[1]))
                  .toList(growable: false);
      });
    } on ApiException {
      if (mounted) {
        setState(() {
          _route = null;
          _routePoints = const [];
        });
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _departure.isBefore(now) ? now : _departure,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure),
    );
    if (!mounted || time == null) return;
    setState(
      () => _departure = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    final from = _from;
    final to = _to;
    if (from == null || to == null) {
      _say('Set where the trip leaves from and where it goes.');
      return;
    }
    if (from.isSameSpotAs(to)) {
      _say('The destination has to be different from the pick-up point.');
      return;
    }
    if (!_departure.isAfter(DateTime.now())) {
      _say('Pick a departure time in the future.');
      return;
    }

    setState(() => _saving = true);
    try {
      final draft = Trip(
        id: '',
        originLabel: from.shortLabel,
        destinationLabel: to.shortLabel,
        departureTime: _departure,
        seatsTotal: _seats,
        seatsAvailable: _seats,
        pricePerSeat: double.parse(_price.text.trim().replaceAll(',', '.')),
        status: 'SCHEDULED',
        instantBooking: _instantBooking,
        originLat: from.lat,
        originLng: from.lng,
        destinationLat: to.lat,
        destinationLng: to.lng,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        distanceM: _route?.distanceM,
        durationS: _route?.durationS,
        routePolyline: _route?.polyline,
      );
      await ReservationService.instance.publishTrip(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: carShareSuccess,
          content: Text('Trip published.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _say(authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: const Text(
        'Publish a trip',
        style: TextStyle(fontWeight: FontWeight.w700, color: carShareText),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PlaceRow(
                    caption: 'FROM',
                    square: false,
                    place: _from,
                    hint: 'Where does the trip start?',
                    onTap: () => _pickPlace(isFrom: true),
                  ),
                  const SizedBox(height: 10),
                  _PlaceRow(
                    caption: 'TO',
                    square: true,
                    place: _to,
                    hint: 'Where does it go?',
                    onTap: () => _pickPlace(isFrom: false),
                  ),
                  if (_routing) ...[
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Working out the route…',
                          style: TextStyle(color: carShareMuted),
                        ),
                      ],
                    ),
                  ],
                  if (_routePoints.length > 1) ...[
                    const SizedBox(height: 14),
                    _RoutePreview(points: _routePoints, route: _route),
                  ],
                  const SizedBox(height: 18),
                  _Field(
                    label: 'Departure',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickDeparture,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: carShareBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 20,
                              color: carShareMuted,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatWhen(_departure),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: carShareText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Field(
                    label: 'Seats',
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatSeats(_seats),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: carShareText,
                            ),
                          ),
                        ),
                        _RoundButton(
                          icon: Icons.remove,
                          onTap: _seats <= 1
                              ? null
                              : () => setState(() => _seats--),
                        ),
                        const SizedBox(width: 8),
                        _RoundButton(
                          icon: Icons.add,
                          filled: true,
                          onTap: _seats >= 8
                              ? null
                              : () => setState(() => _seats++),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  CarShareTextField(
                    controller: _price,
                    label: 'Price per seat (DT)',
                    icon: Icons.payments_outlined,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: _validatePrice,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: carShareBorder),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: carShareGreen,
                      value: _instantBooking,
                      onChanged: (value) =>
                          setState(() => _instantBooking = value),
                      title: const Text(
                        'Instant booking',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: carShareText,
                        ),
                      ),
                      subtitle: const Text(
                        'Seats are confirmed without waiting for you.',
                        style: TextStyle(fontSize: 12, color: carShareMuted),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CarShareTextField(
                    controller: _notes,
                    label: 'Notes (optional)',
                    icon: Icons.sticky_note_2_outlined,
                    validator: (value) =>
                        (value != null && value.trim().length > 500)
                        ? 'Keep the notes under 500 characters.'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
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
                      onPressed: _saving ? null : _publish,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Publish trip',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The API takes a price of zero or more with at most three decimals (millimes).
  String? _validatePrice(String? value) {
    final text = (value ?? '').trim().replaceAll(',', '.');
    if (text.isEmpty) return 'Set a price, or 0 for a free seat.';
    final amount = double.tryParse(text);
    if (amount == null) return 'Enter a number, for example 7.5';
    if (amount < 0) return 'The price cannot be negative.';
    if (amount > 9999) return 'That price looks too high.';
    final dot = text.indexOf('.');
    if (dot >= 0 && text.length - dot - 1 > 3) {
      return 'At most three decimals.';
    }
    return null;
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.caption,
    required this.square,
    required this.place,
    required this.hint,
    required this.onTap,
  });

  final String caption;
  final bool square;
  final Place? place;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: carShareBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: square ? const Color(0xFF065F46) : carShareSuccess,
              shape: square ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: square ? BorderRadius.circular(4) : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: carShareMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  place?.label ?? hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: place == null ? carShareMuted : carShareText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoutePreview extends StatelessWidget {
  const _RoutePreview({required this.points, required this.route});

  final List<LatLng> points;
  final RouteInfo? route;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 170,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(28),
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.none,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.carshare.app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    strokeWidth: 4,
                    color: carShareGreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (route != null) ...[
        const SizedBox(height: 8),
        Text(
          '${formatDistance(route!.distanceM)} · '
          '${formatDuration(route!.durationS)}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: carShareMuted,
          ),
        ),
      ],
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: carShareMuted,
        ),
      ),
      const SizedBox(height: 8),
      child,
    ],
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: filled && enabled ? carShareGreen : carShareBackground,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            size: 20,
            color: filled && enabled
                ? Colors.white
                : (enabled ? carShareText : carShareBorder),
          ),
        ),
      ),
    );
  }
}
