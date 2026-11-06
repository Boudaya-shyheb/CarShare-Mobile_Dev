import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/user_profile.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const _databaseName = 'carshare.db';
  static const _tableName = 'user_profiles';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasePath, _databaseName),
      version: 2,
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
}
