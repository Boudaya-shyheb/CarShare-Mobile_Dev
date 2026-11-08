import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../models/user_profile.dart';
import '../../services/geo_service.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import 'place_search_page.dart';
import 'search_results_page.dart';

/// Mockup 04 — the map, the greeting card, and the "Where to today?" sheet.
class HomeSearchPage extends StatefulWidget {
  const HomeSearchPage({super.key, required this.user});

  final UserProfile user;

  @override
  State<HomeSearchPage> createState() => _HomeSearchPageState();
}

class _HomeSearchPageState extends State<HomeSearchPage> {
  final MapController _map = MapController();

  /// Where the map sits. Starts on Tunis and moves to the device position once it arrives, so
  /// the screen is usable the whole time — including when location is refused.
  LatLng _centre = const LatLng(
    LocationService.tunisLat,
    LocationService.tunisLng,
  );
  bool _hasRealPosition = false;

  Place? _from;
  Place? _to;
  DateTime _departure = _nextHalfHour();
  int _seats = 1;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// The default departure is the next half hour, so "Today, 08:00" is never in the past.
  static DateTime _nextHalfHour() {
    final now = DateTime.now();
    final rounded = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute < 30 ? 30 : 0,
    );
    return now.minute < 30 ? rounded : rounded.add(const Duration(hours: 1));
  }

  Future<void> _locate({bool recentre = false}) async {
    setState(() => _locating = true);
    final position = await LocationService.instance.currentPosition();
    if (!mounted) return;

    if (!position.hasPosition) {
      setState(() => _locating = false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(position.message!),
          action: position.needsSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: LocationService.instance.openSettings,
                )
              : null,
        ),
      );
      return;
    }

    final point = LatLng(position.lat!, position.lng!);
    setState(() {
      _centre = point;
      _hasRealPosition = true;
      _locating = false;
    });
    if (recentre) _map.move(point, 15);

    // Name the street behind the map, for the FROM row. A failure here is not worth a message:
    // describePoint already falls back to the coordinates.
    final label = await GeoService.instance.describePoint(
      position.lat!,
      position.lng!,
    );
    if (!mounted) return;
    setState(() {
      _from = Place(
        label: 'Current location · $label',
        lat: position.lat!,
        lng: position.lng!,
      );
    });
  }

  Future<void> _pickPlace({required bool isFrom}) async {
    final picked = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => PlaceSearchPage(
          title: isFrom ? 'Pick up from' : 'Where to?',
          near:
              _from ??
              Place(
                label: 'Tunis',
                lat: _centre.latitude,
                lng: _centre.longitude,
              ),
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
  }

  void _swap() {
    if (_from == null && _to == null) return;
    setState(() {
      final previousFrom = _from;
      _from = _to;
      _to = previousFrom;
    });
  }

  Future<void> _pickDepartureTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _departure.isBefore(now) ? now : _departure,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure),
    );
    if (!mounted || time == null) return;

    setState(() {
      _departure = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickSeats() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            const _DragHandle(),
            const SizedBox(height: 14),
            const Text(
              'How many seats?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: carShareText,
              ),
            ),
            const SizedBox(height: 8),
            // A fixed handful of rows, so a plain list is fine here.
            ...List.generate(8, (index) {
              final seats = index + 1;
              return ListTile(
                leading: Icon(
                  seats == _seats
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: seats == _seats ? carShareGreen : carShareMuted,
                ),
                title: Text(seats == 1 ? '1 seat' : '$seats seats'),
                onTap: () => Navigator.of(sheetContext).pop(seats),
              );
            }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() => _seats = chosen);
  }

  void _search() {
    final from = _from;
    final to = _to;
    if (from == null || to == null) {
      _say('Choose where you are leaving from and where you are going.');
      return;
    }
    if (from.isSameSpotAs(to)) {
      _say('Pick a destination different from your pickup point.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsPage(
          from: from,
          to: to,
          departureTime: _departure,
          seats: _seats,
        ),
      ),
    );
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  String get _departureLabel {
    final now = DateTime.now();
    final sameDay =
        _departure.year == now.year &&
        _departure.month == now.month &&
        _departure.day == now.day;
    final time = DateFormat('HH:mm').format(_departure);
    return sameDay
        ? 'Today, $time'
        : DateFormat('d MMM, HH:mm').format(_departure);
  }

  String get _initials {
    final parts = widget.user.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    body: Stack(
      children: [
        _buildMap(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _GreetingCard(
              initials: _initials,
              greeting: _greeting,
              name: widget.user.fullName,
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_buildRecenterButton(), _buildSheet()],
          ),
        ),
      ],
    ),
  );

  Widget _buildMap() => FlutterMap(
    mapController: _map,
    options: MapOptions(
      initialCenter: _centre,
      initialZoom: 15,
      minZoom: 4,
      maxZoom: 18,
      interactionOptions: const InteractionOptions(
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.carshare.app',
      ),
      if (_hasRealPosition)
        MarkerLayer(
          markers: [
            Marker(
              point: _centre,
              width: 86,
              height: 86,
              child: const _MeDot(),
            ),
          ],
        ),
    ],
  );

  /// Sits directly above the sheet, so it never collides with it however tall the sheet grows.
  Widget _buildRecenterButton() => Padding(
    padding: const EdgeInsets.only(right: 18, bottom: 14),
    child: Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: const Color(0x22000000),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _locating ? null : () => _locate(recentre: true),
          child: SizedBox(
            width: 52,
            height: 52,
            child: _locating
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.near_me, color: carShareGreen),
          ),
        ),
      ),
    ),
  );

  Widget _buildSheet() => Container(
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: _DragHandle()),
                const SizedBox(height: 18),
                const Text(
                  'Where to today?',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: carShareText,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSearchCard(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Chip(
                      icon: Icons.calendar_today_outlined,
                      label: _departureLabel,
                      onTap: _pickDepartureTime,
                    ),
                    const SizedBox(width: 10),
                    _Chip(
                      icon: Icons.people_outline,
                      label: _seats == 1 ? '1 seat' : '$_seats seats',
                      onTap: _pickSeats,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                    onPressed: _search,
                    child: const Text(
                      'Search',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
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

  Widget _buildSearchCard() => Container(
    decoration: BoxDecoration(
      color: carShareBackground,
      borderRadius: BorderRadius.circular(18),
    ),
    padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _PlaceRow(
                marker: const _GreenDot(),
                label: 'FROM',
                value: _from?.label,
                placeholder: _locating
                    ? 'Finding your location…'
                    : 'Choose a pickup point',
                onTap: () => _pickPlace(isFrom: true),
              ),
              const Divider(height: 1, color: carShareBorder),
              _PlaceRow(
                marker: const _GreenSquare(),
                label: 'TO',
                value: _to?.label,
                placeholder: 'Where are you going?',
                onTap: () => _pickPlace(isFrom: false),
              ),
            ],
          ),
        ),
        _SwapButton(onTap: _swap),
      ],
    ),
  );
}

// --- pieces of the screen -------------------------------------------------------------------

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.initials,
    required this.greeting,
    required this.name,
  });

  final String initials;
  final String greeting;
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [carShareCardShadow],
    ),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: carShareTint,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: carShareGreen,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(fontSize: 13, color: carShareMuted),
              ),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: carShareText,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: carShareBackground,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.notifications_none, color: carShareText),
            tooltip: 'Notifications',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Notifications arrive in a later step.'),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The user's own position: a solid dot inside a soft halo.
class _MeDot extends StatelessWidget {
  const _MeDot();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        // 16% of the brand green, as in the mockup.
        color: carShareGreen.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: carShareGreen,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
    ),
  );
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 5,
    decoration: BoxDecoration(
      color: carShareBorder,
      borderRadius: BorderRadius.circular(999),
    ),
  );
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.marker,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final Widget marker;
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chosen = value != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 30, child: Center(child: marker)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: carShareMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: chosen ? carShareText : carShareMuted,
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
}

class _GreenDot extends StatelessWidget {
  const _GreenDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
    ),
    child: Container(
      width: 12,
      height: 12,
      decoration: const BoxDecoration(
        color: carShareSuccess,
        shape: BoxShape.circle,
      ),
    ),
  );
}

class _GreenSquare extends StatelessWidget {
  const _GreenSquare();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: carShareGreen,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: const SizedBox(
        width: 42,
        height: 42,
        child: Icon(Icons.swap_vert, size: 20, color: carShareGreen),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: carShareBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: carShareText),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: carShareText,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
