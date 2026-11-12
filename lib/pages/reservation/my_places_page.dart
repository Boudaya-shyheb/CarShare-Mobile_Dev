import 'package:flutter/material.dart';

import '../../models/favorite_place.dart';
import '../../services/reservation_local_store.dart';
import '../../theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/favorite_place_widgets.dart';

/// "My places": the full list of favourite places saved on this phone, with rename and delete.
/// Opened from the "Manage" link on Home. The data lives in SQLite (the favorite_places table).
class MyPlacesPage extends StatefulWidget {
  const MyPlacesPage({super.key, required this.userId});

  final String userId;

  @override
  State<MyPlacesPage> createState() => _MyPlacesPageState();
}

class _MyPlacesPageState extends State<MyPlacesPage> {
  final ReservationLocalStore _store = ReservationLocalStore.instance;

  /// The FutureBuilder below shows whatever this future gives; a new future reloads the list.
  late Future<List<FavoritePlace>> _places = _store.getFavorites(widget.userId);

  void _reload() {
    setState(() {
      _places = _store.getFavorites(widget.userId);
    });
  }

  Future<void> _rename(FavoritePlace place, List<FavoritePlace> all) async {
    final name = await askFavoriteName(
      context,
      initialName: place.name,
      takenNames: all.where((other) => other.id != place.id).map((p) => p.name),
    );
    if (name == null || name == place.name) return;
    await _store.renameFavorite(place.id!, name);
    _reload();
  }

  Future<void> _delete(FavoritePlace place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete "${place.name}"?'),
        content: const Text('The place is removed from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: carShareDanger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.deleteFavorite(place.id!);
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(title: const Text('My places')),
    body: FutureBuilder<List<FavoritePlace>>(
      future: _places,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const EmptyState(
            icon: Icons.error_outline,
            title: 'Could not read your places',
            line: 'Try again in a moment.',
          );
        }
        final places = snapshot.data ?? const <FavoritePlace>[];
        if (places.isEmpty) {
          return const EmptyState(
            icon: Icons.star_border_rounded,
            title: 'No saved places yet',
            line: 'While you search for a place, tap its star to save it here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: places.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final place = places[index];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: carShareBorder),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: carShareTint,
                  child: Icon(favoriteIcon(place.name), color: carShareGreen),
                ),
                title: Text(
                  place.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  place.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _rename(place, places),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline,
                        color: carShareDanger,
                      ),
                      onPressed: () => _delete(place),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
