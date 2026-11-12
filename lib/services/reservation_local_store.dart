import 'package:sqflite/sqflite.dart';

import '../models/cached_trips.dart';
import '../models/favorite_place.dart';
import '../models/place.dart';
import '../models/recent_search.dart';
import 'local_database.dart';

/// Everything the Reservation module keeps in SQLite: recent searches, favourite places and
/// the offline copy of My trips.
///
/// Every method takes the signed-in user's id, so two accounts on one phone never see each
/// other's rows. The tables are created by [LocalDatabase.createReservationTables].
class ReservationLocalStore {
  /// [database] is only passed by the tests, which give it an in-memory database. The app
  /// uses [instance], which opens the real `carshare.db`.
  ReservationLocalStore({Future<Database> Function()? database})
    : _database = database ?? (() => LocalDatabase.instance.database);

  static final ReservationLocalStore instance = ReservationLocalStore();

  /// The most searches kept per user; the oldest one goes when an eleventh arrives.
  static const maxRecentSearches = 10;

  final Future<Database> Function() _database;

  // --- recent searches ----------------------------------------------------------------------

  /// Saves a search. If the same pick-up and destination were searched before, that row only
  /// gets a new date (and moves to the top); otherwise a new row is added. Afterwards only the
  /// [maxRecentSearches] newest rows are kept.
  ///
  /// [at] is the search time; the tests pass it, the app leaves it out.
  Future<void> addRecentSearch(
    String userId,
    Place from,
    Place to, {
    DateTime? at,
  }) async {
    final db = await _database();
    final search = RecentSearch.fromPlaces(
      userId,
      from,
      to,
      at ?? DateTime.now(),
    );

    final same = await db.query(
      LocalDatabase.recentSearchesTable,
      where: 'user_id = ? AND origin_label = ? AND dest_label = ?',
      whereArgs: [userId, from.label, to.label],
    );
    if (same.isEmpty) {
      await db.insert(LocalDatabase.recentSearchesTable, search.toMap());
    } else {
      // Same route again: refresh the date and the coordinates, do not add a duplicate.
      await db.update(
        LocalDatabase.recentSearchesTable,
        search.toMap(),
        where: 'id = ?',
        whereArgs: [same.first['id']],
      );
    }

    // Newest first; everything after the tenth row is deleted.
    final rows = await db.query(
      LocalDatabase.recentSearchesTable,
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'searched_at DESC, id DESC',
    );
    for (final row in rows.skip(maxRecentSearches)) {
      await db.delete(
        LocalDatabase.recentSearchesTable,
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// The user's recent searches, newest first.
  Future<List<RecentSearch>> getRecentSearches(
    String userId, {
    int limit = maxRecentSearches,
  }) async {
    final db = await _database();
    final rows = await db.query(
      LocalDatabase.recentSearchesTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'searched_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(RecentSearch.fromMap).toList();
  }

  Future<void> deleteRecentSearch(int id) async {
    final db = await _database();
    await db.delete(
      LocalDatabase.recentSearchesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearRecentSearches(String userId) async {
    final db = await _database();
    await db.delete(
      LocalDatabase.recentSearchesTable,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  // --- favourite places ---------------------------------------------------------------------

  /// Saves [place] under [name] ("Home", "Work"...) and returns the new row id.
  Future<int> addFavorite(String userId, String name, Place place) async {
    final db = await _database();
    final favorite = FavoritePlace(
      userId: userId,
      name: name,
      label: place.label,
      lat: place.lat,
      lng: place.lng,
      createdAt: DateTime.now(),
    );
    return db.insert(LocalDatabase.favoritePlacesTable, favorite.toMap());
  }

  /// The user's favourites, oldest first, so the chips keep the order they were saved in.
  Future<List<FavoritePlace>> getFavorites(String userId) async {
    final db = await _database();
    final rows = await db.query(
      LocalDatabase.favoritePlacesTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(FavoritePlace.fromMap).toList();
  }

  /// Changes only the name; the address and coordinates stay.
  Future<void> renameFavorite(int id, String name) async {
    final db = await _database();
    await db.update(
      LocalDatabase.favoritePlacesTable,
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteFavorite(int id) async {
    final db = await _database();
    await db.delete(
      LocalDatabase.favoritePlacesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- the offline copy of My trips ---------------------------------------------------------

  /// Keeps the API's [json] for one tab of My trips. There is one row per user, kind and
  /// scope, so saving again replaces the previous copy.
  Future<void> saveTripsCache({
    required String userId,
    required String kind,
    required String scope,
    required String json,
    DateTime? at,
  }) async {
    final db = await _database();
    final cache = CachedTrips(
      userId: userId,
      kind: kind,
      scope: scope,
      json: json,
      cachedAt: at ?? DateTime.now(),
    );
    await db.insert(
      LocalDatabase.cachedTripsTable,
      cache.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// The saved copy, or null if that tab was never loaded on this phone.
  Future<CachedTrips?> loadTripsCache({
    required String userId,
    required String kind,
    required String scope,
  }) async {
    final db = await _database();
    final rows = await db.query(
      LocalDatabase.cachedTripsTable,
      where: 'user_id = ? AND kind = ? AND scope = ?',
      whereArgs: [userId, kind, scope],
      limit: 1,
    );
    return rows.isEmpty ? null : CachedTrips.fromMap(rows.first);
  }
}
