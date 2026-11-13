import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../models/trip.dart';
import '../../models/user_profile.dart';
import '../../models/vehicle.dart';
import '../../models/vehicle_registration.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../services/reservation_service.dart';
import '../../services/vehicle_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/trip_formats.dart';
import '../main_shell.dart';
import '../my_vehicles_page.dart';
import '../vehicle_form_page.dart';
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

  /// What the server will check before it accepts a trip: a verified licence and an approved
  /// vehicle. Loaded first, so a driver who cannot publish is told why instead of filling in
  /// a form that is refused at the end.
  late Future<_Requirements> _requirements = _loadRequirements();
  Vehicle? _vehicle;

  /// The seats a trip may offer: never more than the chosen vehicle has.
  int get _maxSeats => (_vehicle?.seatsNumber ?? 8).clamp(1, 8);

  Future<_Requirements> _loadRequirements() async {
    final user = await AuthService.instance.refreshProfile();
    final vehicles = await VehicleService.instance.getVehicles();
    final usable = vehicles.where((vehicle) => vehicle.canDriveTrips).toList();
    // Keep the driver's choice across a reload; otherwise the default vehicle, else the first.
    final keep = usable.where((vehicle) => vehicle.id == _vehicle?.id);
    final preferred = usable.where((vehicle) => vehicle.isDefault);
    _vehicle = keep.isNotEmpty
        ? keep.first
        : preferred.isNotEmpty
        ? preferred.first
        : usable.isEmpty
        ? null
        : usable.first;
    if (_vehicle != null && _seats > _maxSeats) _seats = _maxSeats;
    return _Requirements(user, vehicles);
  }

  void _checkAgain() {
    // A block body: an arrow that assigns the Future would hand it back to setState, which
    // throws before it rebuilds.
    setState(() {
      _requirements = _loadRequirements();
    });
  }

  /// The licence is scanned from the Profile tab, so go there and let the driver come back.
  void _goScanLicense() {
    carShareShellTab.value = 3;
    Navigator.of(context).pop();
  }

  Future<void> _addVehicle() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const VehicleFormPage()));
    if (mounted) _checkAgain();
  }

  Future<void> _manageVehicles() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const MyVehiclesPage()));
    if (mounted) _checkAgain();
  }

  Future<void> _chooseVehicle(List<Vehicle> usable) async {
    final picked = await showModalBottomSheet<Vehicle>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                'Which vehicle will you drive?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
            ),
            for (final vehicle in usable)
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                selected: vehicle.id == _vehicle?.id,
                selectedTileColor: carShareTint,
                leading: const Icon(Icons.directions_car_outlined),
                title: Text(
                  '${vehicle.brand} ${vehicle.model}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${displayVehicleRegistration(vehicle.registrationNumber)} · '
                  '${vehicle.seatsNumber} seats${vehicle.isDefault ? ' · Default' : ''}',
                ),
                trailing: vehicle.id == _vehicle?.id
                    ? const Icon(Icons.check_circle, color: carShareGreen)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(vehicle),
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _vehicle = picked;
      if (_seats > _maxSeats) _seats = _maxSeats;
    });
  }

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
    final vehicle = _vehicle;
    if (vehicle == null) {
      _say('Choose the vehicle you will drive.');
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
        vehicleId: vehicle.id,
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
      if (mounted) {
        _say(authErrorMessage(error));
        // The server may have a fresher answer than the screen (a licence reviewed meanwhile).
        if (error is ApiException &&
            const {
              'license_not_verified',
              'license_expired',
              'vehicle_not_approved',
              'vehicle_not_available',
              'vehicle_not_found',
            }.contains(error.code)) {
          _checkAgain();
        }
      }
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
    body: FutureBuilder<_Requirements>(
      future: _requirements,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    authErrorMessage(snapshot.error!),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: carShareMuted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _checkAgain,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        final requirements = snapshot.data!;
        return requirements.missing.isEmpty
            ? _buildForm(requirements)
            : _buildMissing(requirements);
      },
    ),
  );

  /// The explanation shown instead of the form: one card per thing still missing, each with
  /// the button that fixes it.
  Widget _buildMissing(_Requirements requirements) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: RefreshIndicator(
          onRefresh: () async => _checkAgain(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              const Text(
                'Before you can publish a trip',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Passengers need to know who is driving and in what. Fix the following to start publishing.',
                style: TextStyle(color: carShareMuted, height: 1.4),
              ),
              const SizedBox(height: 18),
              for (final problem in requirements.missing) ...[
                _MissingCard(
                  problem: problem,
                  onScanLicense: _goScanLicense,
                  onAddVehicle: _addVehicle,
                  onManageVehicles: _manageVehicles,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: _checkAgain,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check again'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _vehiclePicker(_Requirements requirements) {
    final usable = requirements.vehicles
        .where((vehicle) => vehicle.canDriveTrips)
        .toList(growable: false);
    final vehicle = _vehicle;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: usable.length > 1 ? () => _chooseVehicle(usable) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: carShareBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.directions_car_outlined, color: carShareGreen),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle == null
                        ? 'Choose a vehicle'
                        : '${vehicle.brand} ${vehicle.model}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: carShareText,
                    ),
                  ),
                  if (vehicle != null)
                    Text(
                      '${displayVehicleRegistration(vehicle.registrationNumber)} · '
                      '${vehicle.seatsNumber} seats'
                      '${vehicle.isDefault ? ' · Default' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: carShareMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (usable.length > 1)
              const Icon(Icons.expand_more, color: carShareMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(_Requirements requirements) => SafeArea(
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
                _Field(label: 'Vehicle', child: _vehiclePicker(requirements)),
                const SizedBox(height: 16),
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
                        onTap: _seats >= _maxSeats
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

/// What the publish rules look at, read fresh from the server when the page opens.
class _Requirements {
  const _Requirements(this.user, this.vehicles);

  final UserProfile user;
  final List<Vehicle> vehicles;

  /// The unmet conditions, in the order the driver should fix them.
  List<_Problem> get missing {
    final problems = <_Problem>[];
    final expiry = user.driverLicenseExpiry;
    final today = DateUtils.dateOnly(DateTime.now());
    switch (user.driverLicenseStatus) {
      case 'APPROVED':
        if (expiry == null || expiry.isBefore(today)) {
          problems.add(_Problem.licenseExpired);
        }
      case 'PENDING_REVIEW':
        problems.add(_Problem.licensePending);
      case 'REJECTED':
        problems.add(_Problem.licenseRejected);
      case 'EXPIRED':
        problems.add(_Problem.licenseExpired);
      default:
        problems.add(_Problem.licenseMissing);
    }
    if (vehicles.isEmpty) {
      problems.add(_Problem.noVehicle);
    } else if (!vehicles.any((vehicle) => vehicle.canDriveTrips)) {
      problems.add(_Problem.vehicleNotApproved);
    }
    return problems;
  }
}

enum _Problem {
  licenseMissing,
  licensePending,
  licenseRejected,
  licenseExpired,
  noVehicle,
  vehicleNotApproved,
}

class _MissingCard extends StatelessWidget {
  const _MissingCard({
    required this.problem,
    required this.onScanLicense,
    required this.onAddVehicle,
    required this.onManageVehicles,
  });

  final _Problem problem;
  final VoidCallback onScanLicense;
  final VoidCallback onAddVehicle;
  final VoidCallback onManageVehicles;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String title,
      String body,
      String? action,
      VoidCallback? onTap,
    ) = switch (problem) {
      _Problem.licenseMissing => (
        Icons.badge_outlined,
        'Verify your driver license',
        'Scan your license from your profile. A CarShare admin checks it, and the photo is deleted after the decision.',
        'Scan driver license',
        onScanLicense,
      ),
      _Problem.licensePending => (
        Icons.hourglass_top_rounded,
        'Your license is being reviewed',
        'You can publish as soon as an admin approves it. Pull down to check again.',
        null,
        null,
      ),
      _Problem.licenseRejected => (
        Icons.report_gmailerrorred_outlined,
        'Your license was not accepted',
        'Scan it again, closer and in better light, so the admin can read it.',
        'Scan driver license',
        onScanLicense,
      ),
      _Problem.licenseExpired => (
        Icons.event_busy_outlined,
        'Your license has expired',
        'Scan the renewed license to publish again.',
        'Scan driver license',
        onScanLicense,
      ),
      _Problem.noVehicle => (
        Icons.directions_car_outlined,
        'Add the vehicle you will drive',
        'Every trip is linked to a vehicle that passengers can see: model, colour and photo.',
        'Add a vehicle',
        onAddVehicle,
      ),
      _Problem.vehicleNotApproved => (
        Icons.pending_actions_outlined,
        'None of your vehicles is approved yet',
        'CarShare support approves each vehicle once. A vehicle that is pending, rejected or reported cannot drive a trip.',
        'Manage vehicles',
        onManageVehicles,
      ),
    };
    return Container(
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: carShareTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: carShareGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: carShareText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(color: carShareMuted, height: 1.4)),
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onTap, child: Text(action)),
            ),
          ],
        ],
      ),
    );
  }
}
