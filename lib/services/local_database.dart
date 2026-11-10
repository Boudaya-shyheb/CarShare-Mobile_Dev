import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/user_profile.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  static const _databaseName = 'carshare.db';
  static const _tableName = 'user_profiles';
  static const _draftTable = 'lost_and_found_drafts';

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
        await _createDraftTable(db);
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

        if (oldVersion < 3) {
          await _createDraftTable(db);
        }
      },
    );

    return _database!;
  }

  Future<void> _createDraftTable(Database db) async {
    await db.execute('''
      CREATE TABLE $_draftTable (
        user_id TEXT NOT NULL PRIMARY KEY,
        report_type TEXT NOT NULL CHECK (report_type IN ('LOST', 'FOUND')),
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        photo BLOB
      )
    ''');
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

  Future<void> saveLostAndFoundDraft({
    required String userId,
    required String reportType,
    required String title,
    required String description,
    Uint8List? photo,
  }) async {
    final db = await database;
    await db.insert(
      _draftTable,
      {
        'user_id': userId,
        'report_type': reportType,
        'title': title,
        'description': description,
        'photo': photo,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>?> getLostAndFoundDraft(String userId) async {
    final rows = await (await database).query(
      _draftTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearLostAndFoundDraft(String userId) async {
    await (await database).delete(
      _draftTable,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}