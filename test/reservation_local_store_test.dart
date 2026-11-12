import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:carshare/models/place.dart';
import 'package:carshare/services/local_database.dart';
import 'package:carshare/services/reservation_local_store.dart';

/// The Reservation module's SQLite code, tested on the computer with sqflite_common_ffi (a
/// desktop SQLite behind the same sqflite API). Each test gets a fresh in-memory database.
void main() {
  sqfliteFfiInit();

  const userId = 'user-1';
  const sousse = Place(label: 'Sousse', lat: 35.82, lng: 10.63);
  const monastir = Place(label: 'Monastir', lat: 35.76, lng: 10.81);

  late Database db;
  late ReservationLocalStore store;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, version) => LocalDatabase.createReservationTables(db),
      ),
    );
    store = ReservationLocalStore(database: () async => db);
  });

  tearDown(() => db.close());

  /// A place that is different for every [n], so searches do not count as the same route.
  Place stop(int n) => Place(label: 'Stop $n', lat: 36.0 + n / 100, lng: 10.0);

  group('recent searches', () {
    test('a saved search comes back with both places', () async {
      await store.addRecentSearch(userId, sousse, monastir);

      final saved = await store.getRecentSearches(userId);

      expect(saved, hasLength(1));
      expect(saved.first.id, isNotNull);
      expect(saved.first.from.label, 'Sousse');
      expect(saved.first.to.label, 'Monastir');
      expect(saved.first.to.lat, 35.76);
    });

    test('the newest search is first', () async {
      final t = DateTime(2026, 11, 10, 8);
      await store.addRecentSearch(userId, sousse, monastir, at: t);
      await store.addRecentSearch(
        userId,
        monastir,
        sousse,
        at: t.add(const Duration(minutes: 5)),
      );

      final saved = await store.getRecentSearches(userId);

      expect(saved.map((s) => s.from.label), ['Monastir', 'Sousse']);
    });

    test('the same route twice is one row with a newer date', () async {
      final t = DateTime(2026, 11, 10, 8);
      await store.addRecentSearch(userId, sousse, monastir, at: t);
      await store.addRecentSearch(
        userId,
        stop(1),
        stop(2),
        at: t.add(const Duration(minutes: 1)),
      );
      await store.addRecentSearch(
        userId,
        sousse,
        monastir,
        at: t.add(const Duration(minutes: 9)),
      );

      final saved = await store.getRecentSearches(userId);

      expect(saved, hasLength(2));
      expect(saved.first.originLabel, 'Sousse'); // moved back to the top
      expect(
        saved.first.searchedAt.toLocal(),
        t.add(const Duration(minutes: 9)),
      );
    });

    test('only the 10 newest searches are kept', () async {
      final t = DateTime(2026, 11, 10, 8);
      for (var i = 1; i <= 12; i++) {
        await store.addRecentSearch(
          userId,
          stop(i),
          monastir,
          at: t.add(Duration(minutes: i)),
        );
      }

      final saved = await store.getRecentSearches(userId);

      expect(saved, hasLength(10));
      expect(saved.first.originLabel, 'Stop 12');
      expect(
        saved.last.originLabel,
        'Stop 3',
      ); // Stop 1 and Stop 2 were deleted
    });

    test('the limit argument returns only the latest rows', () async {
      for (var i = 1; i <= 8; i++) {
        await store.addRecentSearch(userId, stop(i), monastir);
      }

      expect(await store.getRecentSearches(userId, limit: 5), hasLength(5));
    });

    test('delete removes one row and clear removes the user\'s rows', () async {
      await store.addRecentSearch(userId, sousse, monastir);
      await store.addRecentSearch(userId, monastir, sousse);
      await store.addRecentSearch('user-2', sousse, monastir);

      final first = (await store.getRecentSearches(userId)).first;
      await store.deleteRecentSearch(first.id!);
      expect(await store.getRecentSearches(userId), hasLength(1));

      await store.clearRecentSearches(userId);
      expect(await store.getRecentSearches(userId), isEmpty);
      // The other account is untouched.
      expect(await store.getRecentSearches('user-2'), hasLength(1));
    });

    test('each user only sees their own searches', () async {
      await store.addRecentSearch(userId, sousse, monastir);

      expect(await store.getRecentSearches('user-2'), isEmpty);
    });
  });

  group('favourite places', () {
    test('add, list, rename and delete', () async {
      final homeId = await store.addFavorite(userId, 'Home', sousse);
      await store.addFavorite(userId, 'Work', monastir);

      var favorites = await store.getFavorites(userId);
      expect(favorites.map((f) => f.name), ['Home', 'Work']);
      expect(favorites.first.id, homeId);
      expect(favorites.first.place.label, 'Sousse');
      expect(favorites.first.lat, 35.82);

      await store.renameFavorite(homeId, 'Flat');
      favorites = await store.getFavorites(userId);
      expect(favorites.first.name, 'Flat');
      expect(favorites.first.label, 'Sousse'); // only the name changed

      await store.deleteFavorite(homeId);
      favorites = await store.getFavorites(userId);
      expect(favorites.map((f) => f.name), ['Work']);
    });

    test('each user only sees their own favourites', () async {
      await store.addFavorite(userId, 'Home', sousse);

      expect(await store.getFavorites('user-2'), isEmpty);
    });
  });

  group('trips cache', () {
    test('what was saved is loaded back', () async {
      final t = DateTime.utc(2026, 11, 10, 9, 30);
      await store.saveTripsCache(
        userId: userId,
        kind: 'passenger',
        scope: 'upcoming',
        json: '[{"id":"r1"}]',
        at: t,
      );

      final cache = await store.loadTripsCache(
        userId: userId,
        kind: 'passenger',
        scope: 'upcoming',
      );

      expect(cache, isNotNull);
      expect(cache!.json, '[{"id":"r1"}]');
      expect(cache.cachedAt, t);
    });

    test('saving again replaces the old copy', () async {
      for (final json in ['[1]', '[1,2]']) {
        await store.saveTripsCache(
          userId: userId,
          kind: 'driver',
          scope: 'past',
          json: json,
        );
      }

      final cache = await store.loadTripsCache(
        userId: userId,
        kind: 'driver',
        scope: 'past',
      );
      final rows = await db.query(LocalDatabase.cachedTripsTable);

      expect(cache!.json, '[1,2]');
      expect(rows, hasLength(1));
    });

    test('tabs, kinds and users do not share a copy', () async {
      await store.saveTripsCache(
        userId: userId,
        kind: 'passenger',
        scope: 'upcoming',
        json: '[]',
      );

      Future<Object?> load(String user, String kind, String scope) =>
          store.loadTripsCache(userId: user, kind: kind, scope: scope);

      expect(await load(userId, 'passenger', 'past'), isNull);
      expect(await load(userId, 'driver', 'upcoming'), isNull);
      expect(await load('user-2', 'passenger', 'upcoming'), isNull);
    });
  });

  group('upgrade from version 4', () {
    test('adds the new tables and keeps the old data', () async {
      final folder = Directory.systemTemp.createTempSync('carshare_db_');
      final file = path.join(folder.path, 'upgrade.db');
      try {
        // A "version 4" phone: it only has the older tables, with a row in one of them.
        var old = await databaseFactoryFfi.openDatabase(
          file,
          options: OpenDatabaseOptions(
            version: 4,
            onCreate: (db, version) async {
              await db.execute(
                'CREATE TABLE pending_gps_points (id INTEGER PRIMARY KEY, trip_id TEXT)',
              );
              await db.insert('pending_gps_points', {'trip_id': 't1'});
            },
          ),
        );
        await old.close();

        // The same app opens it again at version 5: onUpgrade runs once.
        old = await databaseFactoryFfi.openDatabase(
          file,
          options: OpenDatabaseOptions(
            version: 5,
            onUpgrade: (db, oldVersion, newVersion) async {
              if (oldVersion < 5) {
                await LocalDatabase.createReservationTables(db);
              }
            },
          ),
        );
        final upgraded = ReservationLocalStore(database: () async => old);
        await upgraded.addFavorite(userId, 'Home', sousse);

        expect(await upgraded.getFavorites(userId), hasLength(1));
        expect(
          await old.query('pending_gps_points'),
          hasLength(1),
        ); // untouched
        await old.close();
      } finally {
        folder.deleteSync(recursive: true);
      }
    });

    test('creating the tables twice is harmless', () async {
      await store.addFavorite(userId, 'Home', sousse);

      await LocalDatabase.createReservationTables(db); // IF NOT EXISTS

      expect(await store.getFavorites(userId), hasLength(1));
    });
  });
}
