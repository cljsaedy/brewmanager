import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/database_helper.dart';

import '../helpers/test_database.dart';

// these tests run on the pc, not the tablet
// sqflite_common_ffi lets sqlite run on the pc, and inMemoryDatabasePath makes a fresh db in memory (no file)
void main() {
  late Database db;

  // fake timestamp for rows that need created_at
  const now = '2026-11-01T05:30:00.000Z';

  // runs once before all tests, sets up sqlite for the pc
  setUpAll(() {
    sqfliteFfiInit();
  });

  // runs before every test, new empty db made with the app's real schema code
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.version,
        onConfigure: DatabaseHelper.onConfigure,
        onCreate: DatabaseHelper.onCreate,
        // false = dont reuse the db from the last test
        singleInstance: false,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  // adds a stock item with ok default values, pass only what the test cares about
  Future<int> addStockItem({
    String name = 'Milk',
    String baseUnit = 'ml',
    String countType = 'container',
    double? containerSize = 1000,
    String lowMode = 'containers',
  }) {
    return db.insert('stock_items', {
      'name': name,
      'category': 'Dairy',
      'base_unit': baseUnit,
      'count_type': countType,
      'container_label': 'carton',
      'container_size': containerSize,
      'low_mode': lowMode,
      'low_value': 1,
    });
  }

  Future<int> addMenuItem(
    String name, {
    double? priceHint,
    int noStock = 0,
    int isArchived = 0,
    String? archivedAt,
  }) {
    return db.insert('menu_items', {
      'name': name,
      'category': 'Coffee',
      'price_hint': priceHint,
      'no_stock': noStock,
      'is_archived': isArchived,
      'archived_at': archivedAt,
    });
  }

  // sqlite errors show up as a DatabaseException in dart
  final rejected = throwsA(isA<DatabaseException>());

  group('setup', () {
    test('makes every table', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = rows.map((row) => row['name']).toSet();

      expect(
        names,
        containsAll([
          'app_settings',
          'stock_items',
          'menu_items',
          'recipe_lines',
          'business_days',
          'count_lines',
          'stock_events',
          'tally_lines',
          'day_results',
          'container_checks',
          'corrections',
          'outbox',
        ]),
      );
      // every size is its own menu item now, so there is no sizes table
      expect(names, isNot(contains('menu_sizes')));
    });

    test('foreign keys are turned on', () async {
      final rows = await db.rawQuery('PRAGMA foreign_keys');
      expect(rows.first['foreign_keys'], 1);
    });

    test('a count line for a day that doesnt exist is rejected', () async {
      final itemId = await addStockItem();
      expect(
        db.insert('count_lines', {'day_id': 999, 'stock_item_id': itemId}),
        rejected,
      );
    });
  });

  group('stock items', () {
    test('a good item saves', () async {
      expect(await addStockItem(), greaterThan(0));
    });

    test('unknown base unit is rejected', () async {
      expect(addStockItem(baseUnit: 'kg'), rejected);
    });

    test('same name with different case is rejected', () async {
      await addStockItem(name: 'Milk');
      expect(addStockItem(name: 'MILK'), rejected);
    });

    test('name with spaces at the ends or empty is rejected', () async {
      expect(addStockItem(name: ' Milk '), rejected);
      expect(addStockItem(name: ''), rejected);
    });

    test('container item with no container size is rejected', () async {
      expect(addStockItem(containerSize: null), rejected);
      expect(addStockItem(containerSize: 0), rejected);
    });

    test('number item must use exact low-stock mode', () async {
      expect(
        addStockItem(
          name: 'Fries pack',
          baseUnit: 'pcs',
          countType: 'number',
          containerSize: null,
          lowMode: 'containers',
        ),
        rejected,
      );
      expect(
        await addStockItem(
          name: 'Fries pack',
          baseUnit: 'pcs',
          countType: 'number',
          containerSize: null,
          lowMode: 'exact',
        ),
        greaterThan(0),
      );
    });
  });

  group('menu items', () {
    test('sizes are separate items with their own names', () async {
      await addMenuItem('Iced Americano (Regular)', priceHint: 120);
      expect(
        await addMenuItem('Iced Americano (Large)', priceHint: 140),
        greaterThan(0),
      );
    });

    test('same name with different case is rejected', () async {
      await addMenuItem('Americano');
      expect(addMenuItem('AMERICANO'), rejected);
    });

    test('price below 0 is rejected, no price is fine', () async {
      expect(addMenuItem('Americano', priceHint: -1), rejected);
      expect(await addMenuItem('Mocha'), greaterThan(0));
    });

    test('no_stock must be 0 or 1', () async {
      expect(addMenuItem('Water', noStock: 2), rejected);
      expect(await addMenuItem('Water', noStock: 1), greaterThan(0));
    });

    test('archived menu item without archived_at is rejected', () async {
      expect(addMenuItem('Old drink', isArchived: 1), rejected);
      expect(
        await addMenuItem('Old drink', isArchived: 1, archivedAt: now),
        greaterThan(0),
      );
    });
  });

  group('recipe lines', () {
    late int menuItemId;
    late int milkId;

    setUp(() async {
      menuItemId = await addMenuItem('Spanish Latte (Large)');
      milkId = await addStockItem();
    });

    Future<int> addLine({
      double amount = 150,
      int isArchived = 0,
      String? archivedAt,
    }) {
      return db.insert('recipe_lines', {
        'menu_item_id': menuItemId,
        'stock_item_id': milkId,
        'amount': amount,
        'is_archived': isArchived,
        'created_at': now,
        'archived_at': archivedAt,
      });
    }

    test('amount of 0 is rejected', () async {
      expect(addLine(amount: 0), rejected);
    });

    test(
      'two active lines for the same menu item and stock item are rejected',
      () async {
        await addLine();
        expect(addLine(amount: 180), rejected);
      },
    );

    test(
      'an archived line plus a new active line is fine (recipe edit)',
      () async {
        await addLine(amount: 150, isArchived: 1, archivedAt: now);
        expect(await addLine(amount: 180), greaterThan(0));
      },
    );

    test('archived line without archived_at is rejected', () async {
      expect(addLine(isArchived: 1), rejected);
    });
  });

  group('day results and outbox', () {
    late int dayId;
    late int milkId;

    setUp(() async {
      dayId = await db.insert('business_days', {'business_date': '2026-10-30'});
      milkId = await addStockItem();
    });

    test('a gap on an estimated actual is rejected', () async {
      expect(
        db.insert('day_results', {
          'day_id': dayId,
          'stock_item_id': milkId,
          'expected_qty': 420,
          'actual_qty': 500,
          'actual_is_exact': 0,
          'gap': 80,
        }),
        rejected,
      );
    });

    test('an opening count saves with no actual', () async {
      await db.insert('day_results', {
        'day_id': dayId,
        'stock_item_id': milkId,
        'actual_is_exact': 0,
      });

      final row = (await db.query('day_results')).single;
      expect(row['actual_qty'], isNull);
    });

    test('a gap with no actual is rejected', () async {
      expect(
        db.insert('day_results', {
          'day_id': dayId,
          'stock_item_id': milkId,
          'expected_qty': 420,
          'actual_is_exact': 1,
          'gap': 80,
        }),
        rejected,
      );
    });

    test('same day and item twice in day_results is rejected', () async {
      final row = {
        'day_id': dayId,
        'stock_item_id': milkId,
        'actual_qty': 500,
        'actual_is_exact': 0,
      };
      await db.insert('day_results', row);
      expect(db.insert('day_results', row), rejected);
    });

    test('a recovery email with no day saves', () async {
      final id = await db.insert('outbox', {
        'kind': 'recovery',
        'subject': 'Your recovery code',
        'html_body': '',
        'created_at': now,
      });
      expect(id, greaterThan(0));
    });
  });

  group('upgrade from version 1', () {
    // a real file this time, an in-memory db would be gone after closing it
    late Directory folder;
    late String path;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp('brewmanager_test');
      path = '${folder.path}/old.db';
    });

    tearDown(() async {
      await folder.delete(recursive: true);
    });

    test('menu tables are made again, stock items stay', () async {
      // make a version 1 file with the old menu_sizes tables (just the columns that matter)
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE stock_items (id INTEGER PRIMARY KEY, name TEXT)',
            );
            await db.execute(
              'CREATE TABLE menu_items (id INTEGER PRIMARY KEY, name TEXT)',
            );
            await db.execute(
              'CREATE TABLE menu_sizes (id INTEGER PRIMARY KEY, '
              'menu_item_id INTEGER, label TEXT)',
            );
            await db.execute(
              'CREATE TABLE recipe_lines (id INTEGER PRIMARY KEY, '
              'menu_size_id INTEGER, stock_item_id INTEGER)',
            );
            await db.execute(
              'CREATE TABLE tally_lines (id INTEGER PRIMARY KEY, '
              'day_id INTEGER, menu_size_id INTEGER)',
            );
            await db.execute(
              'CREATE TABLE count_lines (id INTEGER PRIMARY KEY)',
            );
          },
        ),
      );
      await old.insert('stock_items', {'name': 'Milk'});
      await old.close();

      // open it again like the new app does, so onUpgrade runs 1 -> 2
      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.version,
          onConfigure: DatabaseHelper.onConfigure,
          onCreate: DatabaseHelper.onCreate,
          onUpgrade: DatabaseHelper.onUpgrade,
        ),
      );

      final tables = (await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((row) => row['name']).toSet();
      expect(tables, isNot(contains('menu_sizes')));

      // PRAGMA table_info = the columns of a table
      Future<Set<Object?>> columns(String table) async =>
          (await upgraded.rawQuery(
            'PRAGMA table_info($table)',
          )).map((row) => row['name']).toSet();
      expect(await columns('menu_items'), contains('no_stock'));
      expect(await columns('recipe_lines'), contains('menu_item_id'));
      // made with the newest table, so the 2 -> 3 step must not add it again
      expect(await columns('recipe_lines'), contains('input_unit'));
      expect(await columns('tally_lines'), contains('menu_item_id'));

      // the stock item from version 1 is still there, with the 3 -> 4 flag
      final stock = await upgraded.query('stock_items');
      expect(stock.single['name'], 'Milk');
      expect(stock.single['needs_opening_count'], 0);
      expect(await columns('count_lines'), contains('is_opening'));

      await upgraded.close();
    });

    test('version 2 recipe lines stay and get an empty input_unit', () async {
      // a version 2 file: recipe_lines without input_unit (just the columns that matter)
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE recipe_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                menu_item_id INTEGER NOT NULL,
                stock_item_id INTEGER NOT NULL,
                amount REAL NOT NULL
              )
            ''');
            await db.insert('recipe_lines', {
              'menu_item_id': 1,
              'stock_item_id': 1,
              'amount': 150,
            });
            await db.execute(
              'CREATE TABLE stock_items (id INTEGER PRIMARY KEY)',
            );
            await db.execute(
              'CREATE TABLE count_lines (id INTEGER PRIMARY KEY)',
            );
          },
        ),
      );
      await old.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.version,
          onUpgrade: DatabaseHelper.onUpgrade,
        ),
      );

      final line = (await upgraded.query('recipe_lines')).single;
      expect(line['amount'], 150);
      expect(line['input_unit'], isNull);

      await upgraded.close();
    });

    test('version 3 rows stay and get the opening count flags', () async {
      // a version 3 file: no opening count columns yet (just the columns that matter)
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE stock_items (id INTEGER PRIMARY KEY, name TEXT)',
            );
            await db.execute(
              'CREATE TABLE count_lines (id INTEGER PRIMARY KEY, end_qty REAL)',
            );
            await db.insert('stock_items', {'name': 'Milk'});
            await db.insert('count_lines', {'end_qty': 3});
          },
        ),
      );
      await old.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.version,
          onUpgrade: DatabaseHelper.onUpgrade,
        ),
      );

      final stock = (await upgraded.query('stock_items')).single;
      expect(stock['name'], 'Milk');
      expect(stock['needs_opening_count'], 0);
      final line = (await upgraded.query('count_lines')).single;
      expect(line['end_qty'], 3);
      expect(line['is_opening'], 0);

      await upgraded.close();
    });

    test('version 4 day_results lets actual_qty be empty', () async {
      // a version 4 file: the old day_results with actual_qty required
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE stock_items (id INTEGER PRIMARY KEY, name TEXT)',
            );
            await db.execute(
              'CREATE TABLE count_lines (id INTEGER PRIMARY KEY, end_qty REAL)',
            );
            await db.execute(
              'CREATE TABLE day_results (day_id INTEGER, stock_item_id INTEGER, '
              'actual_qty REAL NOT NULL, actual_is_exact INTEGER NOT NULL)',
            );
            await db.insert('stock_items', {'name': 'Milk'});
            await db.insert('count_lines', {'end_qty': 3});
          },
        ),
      );
      await old.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.version,
          onUpgrade: DatabaseHelper.onUpgrade,
        ),
      );

      final columns = await upgraded.rawQuery('PRAGMA table_info(day_results)');
      final actual = columns.firstWhere((c) => c['name'] == 'actual_qty');
      expect(actual['notnull'], 0);
      // the other tables keep their rows
      expect(await upgraded.query('stock_items'), hasLength(1));
      expect(await upgraded.query('count_lines'), hasLength(1));

      await upgraded.close();
    });

    test('version 5 corrections take a day note correction', () async {
      // a version 5 file: corrections only took count and tally
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE stock_items (id INTEGER PRIMARY KEY, name TEXT)',
            );
            await db.execute(
              "CREATE TABLE corrections (id INTEGER PRIMARY KEY, "
              "target TEXT CHECK (target IN ('count', 'tally')))",
            );
            await db.insert('stock_items', {'name': 'Milk'});
          },
        ),
      );
      await old.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.version,
          onUpgrade: DatabaseHelper.onUpgrade,
        ),
      );

      // the business day has to be there for the foreign key, but they are off here
      await upgraded.insert('corrections', {
        'day_id': 1,
        'target': 'day',
        'line_id': 1,
        'field': 'day_note',
        'reason': 'typo',
        'corrected_at': '2026-11-01T10:00:00.000Z',
      });
      expect(await upgraded.query('corrections'), hasLength(1));
      final indexes = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_corrections_day'",
      );
      expect(indexes, hasLength(1));
      // the other tables keep their rows
      expect(await upgraded.query('stock_items'), hasLength(1));

      await upgraded.close();
    });

    test('version 6 stock items stay and get empty typed units', () async {
      // a version 6 file: stock_items had no size_unit or low_unit
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE stock_items (id INTEGER PRIMARY KEY, name TEXT)',
            );
            await db.insert('stock_items', {'name': 'Coffee beans'});
          },
        ),
      );
      await old.close();

      final upgraded = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.version,
          onUpgrade: DatabaseHelper.onUpgrade,
        ),
      );

      final item = (await upgraded.query('stock_items')).single;
      // null = shown in the base unit, like before
      expect(item['name'], 'Coffee beans');
      expect(item['size_unit'], isNull);
      expect(item['low_unit'], isNull);
      await upgraded.update('stock_items', {'low_unit': 'kg'});
      // the CHECK rule is there too
      await expectLater(
        upgraded.update('stock_items', {'low_unit': 'cups'}),
        throwsA(isA<DatabaseException>()),
      );

      await upgraded.close();
    });
  });

  test('a new database takes all 3 correction targets', () async {
    final db = await openTestDatabase();
    final dayId = await db.insert('business_days', {
      'business_date': '2026-11-01',
    });

    for (final target in ['count', 'tally', 'day']) {
      await db.insert('corrections', {
        'day_id': dayId,
        'target': target,
        'line_id': 1,
        'field': 'x',
        'reason': 'typo',
        'corrected_at': '2026-11-01T10:00:00.000Z',
      });
    }
    await expectLater(
      db.insert('corrections', {
        'day_id': dayId,
        'target': 'menu',
        'line_id': 1,
        'field': 'x',
        'reason': 'typo',
        'corrected_at': '2026-11-01T10:00:00.000Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });
}
