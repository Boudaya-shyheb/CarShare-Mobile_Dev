import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../models/favorite_place.dart';
import '../../models/place.dart';
import '../../models/recent_search.dart';
import '../../models/user_profile.dart';
import '../../services/geo_service.dart';
import '../../services/location_service.dart';
import '../../services/reservation_local_store.dart';
import '../../theme.dart';
import '../../widgets/favorite_place_widgets.dart';
import '../../widgets/route_title.dart';
import 'my_places_page.dart';
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

  /// Measures the sheet so the map can lift its centre clear of it.
  final GlobalKey _sheetKey = GlobalKey();

  /// The camera starts here and only ever moves through [_moveTo]; binding the camera to
  /// [_centre] instead would make the view depend on how flutter_map reacts to new options.
  static const LatLng _initialCentre = LatLng(
    LocationService.tunisLat,
    LocationService.tunisLng,
  );

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

  /// SQLite, through the Reservation store: the last searches and the saved places.
  final ReservationLocalStore _store = ReservationLocalStore.instance;
  List<RecentSearch> _recent = const [];
  List<FavoritePlace> _favorites = const [];

  @override
  void initState() {
    super.initState();
    _locate();
    _loadSaved();
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
    _moveTo(point, zoom: recentre ? 15 : null);

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

  /// Centres the map on [point] while keeping it in the band of map the sheet does not cover.
  ///
  /// The map is full-bleed, so its true centre sits behind the sheet: centring on the device
  /// position there would hide the dot entirely. Shifting the camera half a sheet south puts
  /// the dot in the middle of what the user can actually see, as in mockup 04.
  void _moveTo(LatLng point, {double? zoom}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
      final camera = _map.camera;
      final target = zoom ?? camera.zoom;
      if (box == null) {
        _map.move(point, target);
        return;
      }
      final lifted = camera.unprojectAtZoom(
        camera.projectAtZoom(point, target) + Offset(0, box.size.height / 2),
        target,
      );
      _map.move(lifted, target);
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

  Future<void> _search() async {
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
    try {
      await _store.addRecentSearch(widget.user.id, from, to);
    } catch (_) {
      // The history is a convenience: if SQLite fails, the search itself must still run.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchResultsPage(
          from: from,
          to: to,
          departureTime: _departure,
          seats: _seats,
        ),
      ),
    );
    if (mounted) _loadSaved();
  }

  // --- recent searches and favourite places (SQLite) -----------------------------------------

  /// Reads both lists from SQLite: at start, and after anything that may have changed them.
  Future<void> _loadSaved() async {
    final userId = widget.user.id;
    final recent = await _store.getRecentSearches(userId, limit: 5);
    final favorites = await _store.getFavorites(userId);
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _favorites = favorites;
    });
  }

  /// Tap on a recent search: fill the form with its two places and search again.
  void _useRecent(RecentSearch search) {
    setState(() {
      _from = search.from;
      _to = search.to;
    });
    _search();
  }

  Future<void> _deleteRecent(RecentSearch search) async {
    await _store.deleteRecentSearch(search.id!);
    await _loadSaved();
  }

  Future<void> _clearRecent() async {
    await _store.clearRecentSearches(widget.user.id);
    await _loadSaved();
  }

  /// Tap on a favourite chip: ask whether it is the pick-up point or the destination.
  Future<void> _useFavorite(FavoritePlace favorite) async {
    final asPickup = await _chooseOption<bool>(favorite.name, [
      (Icons.trip_origin, 'Use as pick-up point', true),
      (Icons.flag_outlined, 'Use as destination', false),
    ]);
    if (!mounted || asPickup == null) return;
    setState(() {
      if (asPickup) {
        _from = favorite.place;
      } else {
        _to = favorite.place;
      }
    });
  }

  /// Long-press on a favourite chip: rename it or delete it.
  Future<void> _editFavorite(FavoritePlace favorite) async {
    final action = await _chooseOption<String>(favorite.name, [
      (Icons.edit_outlined, 'Rename', 'rename'),
      (Icons.delete_outline, 'Delete', 'delete'),
    ]);
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final name = await askFavoriteName(
        context,
        initialName: favorite.name,
        takenNames: _favorites
            .where((other) => other.id != favorite.id)
            .map((other) => other.name),
      );
      if (name == null) return;
      await _store.renameFavorite(favorite.id!, name);
    } else {
      await _store.deleteFavorite(favorite.id!);
    }
    await _loadSaved();
  }

  Future<void> _managePlaces() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MyPlacesPage(userId: widget.user.id)),
    );
    if (mounted) _loadSaved();
  }

  /// A small bottom sheet with one row per option; pops the value of the row that was tapped.
  Future<T?> _chooseOption<T>(
    String title,
    List<(IconData, String, T)> options,
  ) => showModalBottomSheet<T>(
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 8),
          for (final (icon, label, value) in options)
            ListTile(
              leading: Icon(icon, color: carShareGreen),
              title: Text(label),
              onTap: () => Navigator.of(sheetContext).pop(value),
            ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );

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
            children: [
              _buildRecenterButton(),
              // The sheet grows with the saved lists; past 65% of the screen it scrolls.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                ),
                child: _buildSheet(),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildMap() => FlutterMap(
    mapController: _map,
    options: MapOptions(
      initialCenter: _initialCentre,
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
    key: _sheetKey,
    width: double.infinity,
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      boxShadow: [carShareCardShadow],
    ),
    child: SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
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
                const SizedBox(height: 18),
                _buildFavorites(),
                _buildRecentSearches(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// "Home", "Work"... as chips. Tap to use one, long-press to rename or delete it.
  Widget _buildFavorites() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeader(
        title: 'Favourite places',
        actionLabel: 'Manage',
        onAction: _managePlaces,
      ),
      if (_favorites.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Tap the star on a place while you search to save it here.',
            style: TextStyle(fontSize: 13, color: carShareMuted),
          ),
        )
      else
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _favorites.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final favorite = _favorites[index];
              return _FavouriteChip(
                favorite: favorite,
                onTap: () => _useFavorite(favorite),
                onLongPress: () => _editFavorite(favorite),
              );
            },
          ),
        ),
    ],
  );

  /// The last five searches. Tap one to search it again; the bin deletes it.
  Widget _buildRecentSearches() {
    if (_recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        _SectionHeader(
          title: 'Recent searches',
          actionLabel: 'Clear',
          onAction: _clearRecent,
        ),
        // At most five rows, so a plain loop is enough.
        for (final search in _recent)
          _RecentRow(
            search: search,
            onTap: () => _useRecent(search),
            onDelete: () => _deleteRecent(search),
          ),
      ],
    );
  }

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
            // Without this the Column takes the Stack's full loose height, which stretches
            // the whole card down the screen and pushes the avatar and bell to mid-screen.
            mainAxisSize: MainAxisSize.min,
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
    // An icon-only button reaches the semantics tree with no name at all, so a screen reader
    // announces nothing here. Every other control on this screen is labelled.
    child: Semantics(
      button: true,
      label: 'Swap pick-up and destination',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(Icons.swap_vert, size: 20, color: carShareGreen),
        ),
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

/// A section title with one text button on the right ("Manage", "Clear").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
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
      TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: onAction,
        child: Text(actionLabel),
      ),
    ],
  );
}

/// One favourite place as a chip: its icon and its name.
class _FavouriteChip extends StatelessWidget {
  const _FavouriteChip({
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
  });

  final FavoritePlace favorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Material(
    color: carShareTint,
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(favoriteIcon(favorite.name), size: 17, color: carShareGreen),
            const SizedBox(width: 8),
            Text(
              favorite.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: carShareText,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One recent search: "Origin -> Destination", tap to search again, bin to delete.
class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.search,
    required this.onTap,
    required this.onDelete,
  });

  final RecentSearch search;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Row(
      children: [
        const Icon(Icons.history, size: 20, color: carShareMuted),
        const SizedBox(width: 12),
        Expanded(
          child: RouteTitle(
            origin: search.from.shortLabel,
            destination: search.to.shortLabel,
            fontSize: 15,
          ),
        ),
        IconButton(
          tooltip: 'Remove from recent searches',
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.delete_outline,
            size: 20,
            color: carShareMuted,
          ),
          onPressed: onDelete,
        ),
      ],
    ),
  );
}
