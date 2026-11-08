import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../logic/clock.dart';
import 'database_helper.dart';

// what a picked restore file turned out to be
class BackupCheck {
  const BackupCheck._({required this.isValid, this.madeAt, this.newestDay});

  const BackupCheck.notBrewManager() : this._(isValid: false);

  // true = a brewmanager db this app can open
  final bool isValid;
  // when the backup was made, utc iso text, null for a copy that was not made by Back up
  final String? madeAt;
  // the newest business date in it, YYYY-MM-DD, shown when madeAt is missing
  final String? newestDay;
}

// back up and restore (rule 13), the owner section's settings use this
// a backup is the whole sqlite file, so it has everything: stock, menu, counts, reports, the pin hash
// it never has the api keys, those are only in secure storage (rule 11)
class BackupStore {
  BackupStore(this._db, {Clock clock = utcNow}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  // app_settings key of the last backup time, utc iso text
  // it is saved inside the db before it is copied, so a backup knows its own date for the restore question
  static const String lastBackupKey = 'last_backup_at';

  // the tables every brewmanager db has, a file without them is not one
  static const List<String> _neededTables = [
    'app_settings',
    'stock_items',
    'menu_items',
    'business_days',
    'count_lines',
    'outbox',
  ];

  // when the last backup was made, null = never
  Future<String?> lastBackup() async {
    final rows = await _db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [lastBackupKey],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  // the db file as bytes, ready to save where the owner picks
  // the backup time is saved first so the copy carries it, the old time is given back in case the owner cancels
  Future<({Uint8List bytes, String? oldTime})> snapshot() async {
    final oldTime = await lastBackup();
    await _setLastBackup(_clock().toIso8601String());
    // wal_checkpoint = writes changes still waiting in sqlite's side file into the main file,
    // so the copy has everything (it does nothing when the db doesnt use a side file)
    await _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final bytes = await File(_db.path).readAsBytes();
    return (bytes: bytes, oldTime: oldTime);
  }

  // the owner cancelled saving, so put back the last real backup time
  Future<void> undoSnapshot(String? oldTime) async {
    if (oldTime == null) {
      await _db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [lastBackupKey],
      );
    } else {
      await _setLastBackup(oldTime);
    }
  }

  Future<void> _setLastBackup(String time) {
    return _db.insert('app_settings', {
      'key': lastBackupKey,
      'value': time,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // checks a picked file before the restore question (rule 13), never changes the app's db
  // it is written to a temp file and opened read only, the app's own db isnt touched
  // a newer version than this app knows, or a file without brewmanager's tables, is not valid
  // factory = which sqlite opens it, the app's normal one, tests pass the pc one
  static Future<BackupCheck> check(
    Uint8List bytes, {
    DatabaseFactory? factory,
  }) async {
    final folder = await Directory.systemTemp.createTemp('brewmanager_check');
    final path = '${folder.path}${Platform.pathSeparator}check.db';
    Database? db;
    try {
      await File(path).writeAsBytes(bytes, flush: true);
      db = await (factory ?? databaseFactory).openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      final version = await db.getVersion();
      if (version < 1 || version > DatabaseHelper.version) {
        return const BackupCheck.notBrewManager();
      }
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = {for (final row in tables) row['name'] as String};
      if (!_neededTables.every(names.contains)) {
        return const BackupCheck.notBrewManager();
      }

      final made = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [lastBackupKey],
      );
      final newest = await db.rawQuery(
        "SELECT MAX(business_date) AS date FROM business_days WHERE status != 'draft'",
      );
      return BackupCheck._(
        isValid: true,
        madeAt: made.isEmpty ? null : made.first['value'] as String?,
        newestDay: newest.first['date'] as String?,
      );
    } catch (_) {
      // not a sqlite file at all, or a broken one
      return const BackupCheck.notBrewManager();
    } finally {
      await db?.close();
      await folder.delete(recursive: true);
    }
  }
}
