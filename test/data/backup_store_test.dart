import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/backup_store.dart';
import 'package:brewmanager/data/database_helper.dart';

void main() {
  late Directory folder;
  late Database db;

  // a real db file, like on the tablet (an in-memory test db has no file to copy)
  Future<Database> openFileDatabase(String name) {
    return databaseFactoryFfi.openDatabase(
      '${folder.path}${Platform.pathSeparator}$name',
      options: OpenDatabaseOptions(
        version: DatabaseHelper.version,
        onConfigure: DatabaseHelper.onConfigure,
        onCreate: DatabaseHelper.onCreate,
        singleInstance: false,
      ),
    );
  }

  setUp(() async {
    sqfliteFfiInit();
    folder = await Directory.systemTemp.createTemp('brewmanager_backup_test');
    db = await openFileDatabase('app.db');
  });

  tearDown(() async {
    await db.close();
    await folder.delete(recursive: true);
  });

  BackupStore store() =>
      BackupStore(db, clock: () => DateTime.utc(2026, 11, 9, 7, 15));

  test('a backup carries its own time and the data', () async {
    await db.insert('business_days', {
      'business_date': '2026-11-08',
      'status': 'submitted',
    });

    final snapshot = await store().snapshot();
    final check = await BackupStore.check(
      snapshot.bytes,
      factory: databaseFactoryFfi,
    );

    expect(snapshot.oldTime, isNull);
    expect(await store().lastBackup(), '2026-11-09T07:15:00.000Z');
    expect(check.isValid, isTrue);
    expect(check.madeAt, '2026-11-09T07:15:00.000Z');
    expect(check.newestDay, '2026-11-08');
  });

  test('cancelling puts the last real backup time back', () async {
    await db.insert('app_settings', {
      'key': BackupStore.lastBackupKey,
      'value': '2026-11-01T07:00:00.000Z',
    });

    final snapshot = await store().snapshot();
    await store().undoSnapshot(snapshot.oldTime);

    expect(await store().lastBackup(), '2026-11-01T07:00:00.000Z');
  });

  test('cancelling the very first backup leaves "never"', () async {
    final snapshot = await store().snapshot();
    await store().undoSnapshot(snapshot.oldTime);

    expect(await store().lastBackup(), isNull);
  });

  test('a file that is not sqlite is not a backup', () async {
    final check = await BackupStore.check(
      Uint8List.fromList('hello'.codeUnits),
      factory: databaseFactoryFfi,
    );

    expect(check.isValid, isFalse);
  });

  test('a sqlite file without brewmanager tables is not a backup', () async {
    final other = await databaseFactoryFfi.openDatabase(
      '${folder.path}${Platform.pathSeparator}other.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('CREATE TABLE notes (text TEXT)'),
        singleInstance: false,
      ),
    );
    await other.close();
    final bytes = await File(
      '${folder.path}${Platform.pathSeparator}other.db',
    ).readAsBytes();

    final check = await BackupStore.check(bytes, factory: databaseFactoryFfi);

    expect(check.isValid, isFalse);
  });

  test('a backup from a newer app version is not accepted', () async {
    await db.setVersion(DatabaseHelper.version + 1);
    final snapshot = await store().snapshot();

    final check = await BackupStore.check(
      snapshot.bytes,
      factory: databaseFactoryFfi,
    );

    expect(check.isValid, isFalse);
  });

  test('the check never changes the app db', () async {
    final snapshot = await store().snapshot();
    await BackupStore.check(snapshot.bytes, factory: databaseFactoryFfi);

    // the app db is still open and works
    expect(await db.query('app_settings'), isNotEmpty);
  });

  // android 9+ saves db files in wal mode, the pc doesnt, so this makes the tablet's kind of file
  test('a backup saved in wal mode (like android) is accepted', () async {
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.insert('business_days', {
      'business_date': '2026-11-08',
      'status': 'submitted',
    });

    final snapshot = await store().snapshot();
    // byte 18 of a sqlite file is 2 when the file is in wal mode
    expect(snapshot.bytes[18], 2);
    final check = await BackupStore.check(
      snapshot.bytes,
      factory: databaseFactoryFfi,
    );

    expect(check.isValid, isTrue);
    expect(check.newestDay, '2026-11-08');
  });

  test('a file that cant be opened says why', () async {
    final check = await BackupStore.check(
      Uint8List.fromList('hello'.codeUnits),
      factory: databaseFactoryFfi,
    );

    expect(check.isValid, isFalse);
    expect(check.problem, isNotNull);
  });
}
