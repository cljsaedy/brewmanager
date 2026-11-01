import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/database_helper.dart';

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

  Future<int> addMenuItem(String name) {
    return db.insert('menu_items', {'name': name, 'category': 'Coffee'});
  }

  Future<int> addSize(int menuItemId, String label) {
    return db.insert('menu_sizes', {
      'menu_item_id': menuItemId,
      'label': label,
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
          'menu_sizes',
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

  group('menu sizes', () {
    test(
      'same label twice on one menu item is rejected, ignoring case',
      () async {
        final latte = await addMenuItem('Spanish Latte');
        await addSize(latte, 'Large');
        expect(addSize(latte, 'large'), rejected);
      },
    );

    test('same label on two different menu items is fine', () async {
      final latte = await addMenuItem('Spanish Latte');
      final mocha = await addMenuItem('Mocha');
      await addSize(latte, 'Large');
      expect(await addSize(mocha, 'Large'), greaterThan(0));
    });
  });

  group('recipe lines', () {
    late int sizeId;
    late int milkId;

    setUp(() async {
      final latte = await addMenuItem('Spanish Latte');
      sizeId = await addSize(latte, 'Large');
      milkId = await addStockItem();
    });

    Future<int> addLine({
      double amount = 150,
      int isArchived = 0,
      String? archivedAt,
    }) {
      return db.insert('recipe_lines', {
        'menu_size_id': sizeId,
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

    test('two active lines for the same size and item are rejected', () async {
      await addLine();
      expect(addLine(amount: 180), rejected);
    });

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
}
