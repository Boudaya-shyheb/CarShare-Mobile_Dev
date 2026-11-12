import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class SupportLocalDatabase {
  SupportLocalDatabase._();

  static final SupportLocalDatabase instance = SupportLocalDatabase._();
  static const _databaseName = 'carshare_support.db';
  static const _ticketTable = 'cached_support_tickets';
  static const _categoryTable = 'cached_support_categories';
  static const _draftTable = 'support_ticket_drafts';

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(
      path.join(root, _databaseName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_ticketTable (
            user_id TEXT NOT NULL,
            ticket_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            cached_at TEXT NOT NULL,
            PRIMARY KEY (user_id, ticket_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE $_categoryTable (
            category_id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            cached_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_draftTable (
            user_id TEXT PRIMARY KEY,
            trip_id TEXT,
            reservation_id TEXT,
            category_id TEXT,
            category_name TEXT NOT NULL,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> cacheTickets(
    String userId,
    List<Map<String, dynamic>> tickets,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        _ticketTable,
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      for (final ticket in tickets) {
        final id = ticket['id'] as String?;
        if (id == null) continue;
        await transaction.insert(_ticketTable, {
          'user_id': userId,
          'ticket_id': id,
          'payload': jsonEncode(ticket),
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> cachedTickets(String userId) async {
    final rows = await (await database).query(
      _ticketTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'cached_at DESC',
    );
    return rows
        .map((row) => jsonDecode(row['payload']! as String))
        .cast<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<void> cacheCategories(List<Map<String, dynamic>> categories) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(_categoryTable);
      for (final category in categories) {
        final id = category['id'] as String?;
        if (id == null) continue;
        await transaction.insert(_categoryTable, {
          'category_id': id,
          'payload': jsonEncode(category),
          'cached_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> cachedCategories() async {
    final rows = await (await database).query(
      _categoryTable,
      orderBy: 'cached_at DESC',
    );
    return rows
        .map((row) => jsonDecode(row['payload']! as String))
        .cast<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<void> saveDraft({
    required String userId,
    required String categoryName,
    required String title,
    required String description,
    String? tripId,
    String? reservationId,
    String? categoryId,
  }) async {
    await (await database).insert(_draftTable, {
      'user_id': userId,
      'trip_id': tripId,
      'reservation_id': reservationId,
      'category_id': categoryId,
      'category_name': categoryName,
      'title': title,
      'description': description,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> draft(String userId) async {
    final rows = await (await database).query(
      _draftTable,
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearDraft(String userId) async {
    await (await database).delete(
      _draftTable,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
