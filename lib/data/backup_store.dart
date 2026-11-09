import 'dart:io';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../logic/clock.dart';
import 'database_helper.dart';

// what a picked restore file turned out to be
class BackupCheck {
  const BackupCheck._({
    required this.isValid,
    this.madeAt,
    this.newestDay,
    this.problem,
  });

  // problem = the error when the file couldnt be opened at all, null when it opened but isnt brewmanager's
  const BackupCheck.notBrewManager({String? problem})
    : this._(isValid: false, problem: problem);

  // true = a brewmanager db this app can open
  final bool isValid;
  // why the file couldnt be opened, shown to the owner so a problem on the tablet can be found
  final String? problem;
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
  // it is written to a throwaway copy and opened from there, the app's own db isnt touched
  // a newer version than this app knows, or a file without brewmanager's tables, is not valid
  // factory = which sqlite opens it, the app's normal one, tests pass the pc one
  //
  // why not read only: android 9+ saves its db files in wal mode (recent changes kept in a side file),
  // and sqlite cant open a wal file read only when its side files arent there, so it would always fail
  // the copy is thrown away after, so opening it normally is safe
  // why the db folder: it is always writable by the app, dart's own temp folder isnt always on android
  static Future<BackupCheck> check(
    Uint8List bytes, {
    DatabaseFactory? factory,
  }) async {
    final opener = factory ?? databaseFactory;
    final folder = Directory(
      '${await opener.getDatabasesPath()}${Platform.pathSeparator}restore_check',
    );
    final path = '${folder.path}${Platform.pathSeparator}check.db';
    Database? db;
    try {
      // a left over copy from a check that crashed goes first
      if (await folder.exists()) await folder.delete(recursive: true);
      await folder.create(recursive: true);
      await File(path).writeAsBytes(bytes, flush: true);
      db = await opener.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
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
    } catch (error) {
      // not a sqlite file at all, a broken one, or the tablet couldnt write the copy
      // the error goes along so the settings screen can show what really happened
      return BackupCheck.notBrewManager(problem: error.toString());
    } finally {
      await db?.close();
      // the copy is only a check, it can stay if deleting fails, the next check removes it first
      try {
        await folder.delete(recursive: true);
      } catch (_) {}
    }
  }
}

// app_settings key of the one-time marker that tells if a restore really took
const String restoreMarkerKey = 'restore_marker';

// restore (rule 13): copies a checked backup's data into the db in use, gives back true when it really took
//
// why not swap the db file: on android the system keeps its own hold on an open db file,
// so writing a new file under it and opening it again still showed the old data (found on the tablet)
// so the db is never closed: the backup is attached next to it and copied in, table by table
//
// steps:
// 1 the backup goes to a working copy, opened once with the app's upgrade code so an older backup
//   gets the same tables and columns as this app
// 2 ATTACH = sqlite opens that copy next to the db in use, as "backup"
// 3 in 1 transaction: every table is emptied and filled from the backup (all or nothing)
//   columns are matched by name, so a column added later in a different place still lines up
// 4 the copy is detached and deleted
//
// how it knows it took: a one-time marker is written in the db in use first, the backup never has it,
// so after the copy it must be gone
// db and factory = the db in use and which sqlite opens the copy, tests pass their own
Future<bool> restoreAndCheck(
  Uint8List bytes, {
  Database? db,
  DatabaseFactory? factory,
}) async {
  final live = db ?? await DatabaseHelper.database;
  final opener = factory ?? databaseFactory;
  final folder = Directory(
    '${await opener.getDatabasesPath()}${Platform.pathSeparator}restore_copy',
  );
  final path = '${folder.path}${Platform.pathSeparator}backup.db';

  final marker = DateTime.now().microsecondsSinceEpoch.toString();
  await live.insert('app_settings', {
    'key': restoreMarkerKey,
    'value': marker,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  try {
    // 1 the working copy, brought up to this app's tables
    if (await folder.exists()) await folder.delete(recursive: true);
    await folder.create(recursive: true);
    await File(path).writeAsBytes(bytes, flush: true);
    final copy = await opener.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.version,
        onConfigure: DatabaseHelper.onConfigure,
        onUpgrade: DatabaseHelper.onUpgrade,
        singleInstance: false,
      ),
    );
    await copy.close();

    // foreign keys off while tables are emptied and filled in any order, on again after
    // (this pragma cant change inside a transaction, so it is set around it)
    await live.execute('PRAGMA foreign_keys = OFF');
    // 2 attach, the path is a parameter so a folder name with a quote cant break the sql
    await live.execute('ATTACH DATABASE ? AS backup', [path]);
    try {
      // 3 everything in 1 transaction
      await live.transaction((txn) async {
        final tables = await txn.rawQuery(
          "SELECT name FROM main.sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        );
        for (final row in tables) {
          await _copyTable(txn, row['name'] as String);
        }
        // the autoincrement counters, so new rows get ids after the backup's
        await _copyTable(txn, 'sqlite_sequence');
      });
    } finally {
      // 4 detach and foreign keys on again, even when the copy failed
      await live.execute('DETACH DATABASE backup');
      await live.execute('PRAGMA foreign_keys = ON');
    }
  } finally {
    try {
      await folder.delete(recursive: true);
    } catch (_) {}
  }

  final rows = await live.query(
    'app_settings',
    where: 'key = ?',
    whereArgs: [restoreMarkerKey],
  );
  final took = rows.isEmpty || rows.first['value'] != marker;
  if (!took) {
    await live.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [restoreMarkerKey],
    );
  }
  return took;
}

// empties 1 table of the db in use and fills it from the attached backup
// only the columns both have, matched by name
// a table the backup doesnt have just ends up empty (it was added after that backup, nothing to bring back)
Future<void> _copyTable(Transaction txn, String table) async {
  Future<List<String>> columnsOf(String schema) async {
    final rows = await txn.rawQuery('PRAGMA $schema.table_info("$table")');
    return [for (final row in rows) row['name'] as String];
  }

  final mainColumns = await columnsOf('main');
  if (mainColumns.isEmpty) return;
  await txn.execute('DELETE FROM main."$table"');
  final backupColumns = (await columnsOf('backup')).toSet();
  final shared = [
    for (final column in mainColumns)
      if (backupColumns.contains(column)) '"$column"',
  ];
  if (shared.isEmpty) return;
  final list = shared.join(', ');
  await txn.execute(
    'INSERT INTO main."$table" ($list) SELECT $list FROM backup."$table"',
  );
}
