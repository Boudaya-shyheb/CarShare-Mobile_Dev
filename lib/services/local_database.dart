import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/user_profile.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const _databaseName = 'carshare.db';
  static const _tableName = 'user_profiles';

  /// GPS fixes the driver recorded while the API could not be reached. Flushed in order on
  /// the next successful send, so a dead spot leaves a gap that fills itself in.
  static const _gpsTableName = 'pending_gps_points';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasePath, _databaseName),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            full_name TEXT NOT NULL,
            phone TEXT NOT NULL,
            email TEXT NOT NULL,
            role TEXT NOT NULL,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'ACTIVE',
            status_until TEXT,
            has_profile_photo INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await _createGpsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN status TEXT NOT NULL DEFAULT 'ACTIVE'",
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN status_until TEXT',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN has_profile_photo INTEGER NOT NULL DEFAULT 0',
          );
        }
        // Version 3 only adds the GPS buffer; user_profiles is left exactly as it was.
        if (oldVersion < 3) {
          await _createGpsTable(db);
        }
      },
    );
    return _database!;
  }

  Future<UserProfile?> getProfile() async {
    final rows = await (await database).query(_tableName, limit: 1);
    return rows.isEmpty ? null : UserProfile.fromMap(rows.first);
  }

  Future<void> saveProfile(UserProfile profile) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(_tableName);
      await transaction.insert(
        _tableName,
        profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> clearProfile() async {
    await (await database).delete(_tableName);
  }

  // --- the driver's offline GPS buffer -------------------------------------------------------

  static Future<void> _createGpsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_gpsTableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id TEXT NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        speed_mps REAL,
        recorded_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX ix_pending_gps_trip ON $_gpsTableName (trip_id, id)',
    );
  }

  /// Keeps points that could not be sent. `id` orders them, so they go out oldest first.
  Future<void> bufferGpsPoints(
    String tripId,
    List<Map<String, Object?>> points,
  ) async {
    if (points.isEmpty) return;
    final db = await database;
    await db.transaction((transaction) async {
      for (final point in points) {
        await transaction.insert(_gpsTableName, {
          'trip_id': tripId,
          'lat': point['lat'],
          'lng': point['lng'],
          'speed_mps': point['speedMps'],
          'recorded_at': point['recordedAt'],
        });
      }
    });
  }

  /// The oldest buffered points for a trip, with their row ids so they can be deleted once
  /// the API has taken them. [limit] matches the endpoint's cap of 50 points per call.
  Future<List<Map<String, Object?>>> pendingGpsPoints(
    String tripId, {
    int limit = 50,
  }) async => (await database).query(
    _gpsTableName,
    where: 'trip_id = ?',
    whereArgs: [tripId],
    orderBy: 'id ASC',
    limit: limit,
  );

  Future<void> deleteGpsPoints(List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await (await database).delete(
      _gpsTableName,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<int> pendingGpsCount(String tripId) async {
    final rows = await (await database).rawQuery(
      'SELECT COUNT(*) AS n FROM $_gpsTableName WHERE trip_id = ?',
      [tripId],
    );
    return (rows.first['n'] as int?) ?? 0;
  }
}
