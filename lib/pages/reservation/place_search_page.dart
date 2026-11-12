import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/favorite_place.dart';
import '../../models/place.dart';
import '../../services/auth_service.dart';
import '../../services/geo_service.dart';
import '../../services/location_service.dart';
import '../../services/reservation_local_store.dart';
import '../../theme.dart';
import '../../widgets/favorite_place_widgets.dart';

/// Picks one end of a trip: by typing, from the device position, or from the map.
///
/// Pops a [Place], or null if the user backs out.
class PlaceSearchPage extends StatefulWidget {
  const PlaceSearchPage({super.key, required this.title, this.near});

  /// "Pick up from" or "Where to?", so the screen says which end is being set.
  final String title;

  /// Where to open the map picker, usually the user's position.
  final Place? near;

  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _searching = false;
  bool _locating = false;
  String? _error;

  /// The saved places, from SQLite, so a result that is already saved shows a filled star.
  final ReservationLocalStore _store = ReservationLocalStore.instance;
  List<FavoritePlace> _favorites = const [];

  String? get _userId => AuthService.instance.currentUser.value?.id;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final userId = _userId;
    if (userId == null) return;
    final favorites = await _store.getFavorites(userId);
    if (!mounted) return;
    setState(() => _favorites = favorites);
  }

  /// The star on a result: ask for a name in a dialog, then save the place in SQLite.
  Future<void> _saveFavorite(Place place) async {
    final userId = _userId;
    if (userId == null) return;
    final name = await askFavoriteName(
      context,
      takenNames: _favorites.map((favorite) => favorite.name),
    );
    if (!mounted || name == null) return;
    await _store.addFavorite(userId, name, place);
    await _loadFavorites();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved as $name.')));
  }

  /// True when this exact spot is already one of the saved places.
  bool _isSaved(Place place) =>
      _favorites.any((favorite) => favorite.place.isSameSpotAs(place));

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  /// One request per pause in typing, not one per keystroke: Nominatim asks for no more than
  /// one call a second and would otherwise start refusing them.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(GeoService.searchDebounce, () => _search(value));
  }

  Future<void> _search(String query) async {
    try {
      final found = await GeoService.instance.searchPlaces(query);
      if (!mounted) return;
      // A slower earlier request must not overwrite what is in the field now.
      if (query.trim() != _queryController.text.trim()) return;
      setState(() {
        _results = found;
        _searching = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = authErrorMessage(error);
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final position = await LocationService.instance.currentPosition();
      if (!mounted) return;
      if (!position.hasPosition) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(position.message!)));
        return;
      }
      final label = await GeoService.instance.describePoint(
        position.lat!,
        position.lng!,
      );
      if (!mounted) return;
      Navigator.of(context)
          .pop(Place(label: label, lat: position.lat!, lng: position.lng!));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final start = widget.near;
    final picked = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => _MapPickerPage(
          centre: LatLng(
            start?.lat ?? LocationService.tunisLat,
            start?.lng ?? LocationService.tunisLng,
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: carShareText,
        ),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: TextField(
                  controller: _queryController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'Search a place in Tunisia',
                    prefixIcon: const Icon(Icons.search, color: carShareMuted),
                    suffixIcon: _queryController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, color: carShareMuted),
                            onPressed: () {
                              _queryController.clear();
                              _onQueryChanged('');
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ActionRow(
                icon: Icons.my_location,
                label: 'Use current location',
                loading: _locating,
                onTap: _locating ? null : _useCurrentLocation,
              ),
              _ActionRow(
                icon: Icons.map_outlined,
                label: 'Pick on map',
                onTap: _pickOnMap,
              ),
              const Divider(height: 24, color: carShareBorder),
              Expanded(child: _buildResults()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildResults() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Hint(icon: Icons.cloud_off, text: _error!);
    }
    if (_queryController.text.trim().length < 2) {
      return const _Hint(
        icon: Icons.place_outlined,
        text:
            'Type at least two letters to search,\nor pick a point on the map.',
      );
    }
    if (_results.isEmpty) {
      return const _Hint(
        icon: Icons.search_off,
        text: 'Nothing found. Try a different spelling.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 56, color: carShareBorder),
      itemBuilder: (context, index) {
        final place = _results[index];
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(place),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                const SizedBox(
                  width: 40,
                  child: Icon(Icons.location_on_outlined, color: carShareGreen),
                ),
                Expanded(
                  child: Text(
                    place.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: carShareText,
                    ),
                  ),
                ),
                if (_userId != null)
                  IconButton(
                    tooltip: _isSaved(place)
                        ? 'Saved in My places'
                        : 'Save to My places',
                    icon: Icon(
                      _isSaved(place) ? Icons.star : Icons.star_border,
                      color: _isSaved(place) ? carShareWarning : carShareMuted,
                    ),
                    onPressed: _isSaved(place)
                        ? null
                        : () => _saveFavorite(place),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: carShareGreen),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: carShareGreen,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: carShareBorder),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted, height: 1.4),
          ),
        ],
      ),
    ),
  );
}

/// Drag the map under a fixed centre pin, then Confirm. Pops the [Place] under the pin.
class _MapPickerPage extends StatefulWidget {
  const _MapPickerPage({required this.centre});

  final LatLng centre;

  @override
  State<_MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<_MapPickerPage> {
  final MapController _map = MapController();
  bool _confirming = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);
    final centre = _map.camera.center;
    final label = await GeoService.instance.describePoint(
      centre.latitude,
      centre.longitude,
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    Navigator.of(context)
        .pop(Place(label: label, lat: centre.latitude, lng: centre.longitude));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: const Text(
        'Pick on map',
        style: TextStyle(fontWeight: FontWeight.w700, color: carShareText),
      ),
    ),
    body: Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: widget.centre, initialZoom: 15),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.carshare.app',
            ),
          ],
        ),
        // The pin sits still in the middle while the map moves under it.
        const IgnorePointer(
          child: Center(
            child: Padding(
              // Lifts the point of the pin onto the centre of the viewport.
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(
                Icons.location_on,
                size: 44,
                color: carShareGreen,
                shadows: [Shadow(color: Color(0x33000000), blurRadius: 8)],
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          // The map is full-bleed under the system navigation bar, so the button has to be
          // lifted clear of it by hand: without this inset the label is cut in half.
          bottom: 24 + MediaQuery.of(context).padding.bottom,
          child: SizedBox(
            height: carShareButtonHeight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(carShareButtonRadius),
                ),
              ),
              onPressed: _confirming ? null : _confirm,
              child: _confirming
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Confirm this point',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ],
    ),
  );
}
