import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/backup_store.dart';
import 'package:brewmanager/data/database_helper.dart';

import '../helpers/test_database.dart';

// the real restore: a backup's data copied into the db in use, which is never closed
void main() {
  late Directory folder;
  late Database live;

  setUp(() async {
    sqfliteFfiInit();
    folder = await Directory.systemTemp.createTemp('brewmanager_restore');
    // the working copy goes in the db folder, here a temp folder so nothing real is touched
    await databaseFactoryFfi.setDatabasesPath(folder.path);
    live = await openTestDatabase();
  });

  tearDown(() async {
    await live.close();
    await folder.delete(recursive: true);
  });

  // a real db file with the app's tables, as bytes, like a backup file
  // change = what to put in it before it is copied
  Future<Uint8List> makeBackup(
    Future<void> Function(Database db) change,
  ) async {
    final path = '${folder.path}${Platform.pathSeparator}made.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.version,
        onConfigure: DatabaseHelper.onConfigure,
        onCreate: DatabaseHelper.onCreate,
        singleInstance: false,
      ),
    );
    await change(db);
    await db.close();
    final bytes = await File(path).readAsBytes();
    await File(path).delete();
    return bytes;
  }

  Future<List<String>> names(String table) async {
    final rows = await live.query(table, orderBy: 'id');
    return [for (final row in rows) row['name'] as String];
  }

  Future<bool> restore(Uint8List bytes) {
    return restoreAndCheck(bytes, db: live, factory: databaseFactoryFfi);
  }

  test('the backup data replaces what is there now', () async {
    final backup = await makeBackup((db) async {
      await db.insert('menu_items', {'name': 'Latte', 'category': 'Coffee'});
      await db.insert('business_days', {
        'business_date': '2026-11-08',
        'status': 'submitted',
      });
    });
    // what the tablet has now, made after the backup
    await live.insert('menu_items', {'name': 'Mocha', 'category': 'Coffee'});
    await live.insert('menu_items', {'name': 'Tea', 'category': 'Drinks'});

    expect(await restore(backup), isTrue);

    expect(await names('menu_items'), ['Latte']);
    final days = await live.query('business_days');
    expect(days.single['business_date'], '2026-11-08');
  });

  test('the marker never stays, foreign keys are on again', () async {
    final backup = await makeBackup((_) async {});

    await restore(backup);

    expect(
      await live.query('app_settings', where: "key = '$restoreMarkerKey'"),
      isEmpty,
    );
    final keys = await live.rawQuery('PRAGMA foreign_keys');
    expect(keys.single.values.single, 1);
  });

  test('new rows after a restore get ids after the backup ones', () async {
    final backup = await makeBackup((db) async {
      for (final name in ['A', 'B', 'C']) {
        await db.insert('menu_items', {'name': name, 'category': 'X'});
      }
    });

    await restore(backup);
    final id = await live.insert('menu_items', {'name': 'D', 'category': 'X'});

    expect(id, 4);
  });

  test('a backup from an older app version is brought up to date', () async {
    final backup = await makeBackup((db) async {
      await db.insert('business_days', {
        'business_date': '2026-11-08',
        'status': 'submitted',
      });
      // like a version 7 backup: no ai_outcome column yet
      await db.execute('ALTER TABLE business_days DROP COLUMN ai_outcome');
      await db.setVersion(7);
    });

    expect(await restore(backup), isTrue);

    final day = (await live.query('business_days')).single;
    expect(day['business_date'], '2026-11-08');
    expect(day.containsKey('ai_outcome'), isTrue);
    expect(day['ai_outcome'], isNull);
  });

  test('the working copy is deleted after', () async {
    final backup = await makeBackup((_) async {});

    await restore(backup);

    expect(
      Directory(
        '${folder.path}${Platform.pathSeparator}restore_copy',
      ).existsSync(),
      isFalse,
    );
  });
}
