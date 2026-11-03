import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/units.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late MenuItemStore store;
  late RecipeStore recipes;
  late StockItemStore stock;
  // fake clock, tests move it forward to get known times
  late DateTime now;

  setUp(() async {
    db = await openTestDatabase();
    now = DateTime.utc(2026, 11, 1, 8);
    store = MenuItemStore(db, clock: () => now);
    recipes = RecipeStore(db, clock: () => now);
    stock = StockItemStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // checks that it fails with this plain words message
  Future<void> expectProblem(Future<void> Function() save, String message) {
    return expectLater(
      save,
      throwsA(
        isA<MenuItemException>().having((e) => e.message, 'message', message),
      ),
    );
  }

  Future<int> addStock(String name) {
    return stock.add(
      StockItem(
        name: name,
        category: 'Dairy',
        baseUnit: BaseUnit.ml,
        countType: CountType.container,
        containerSize: 1000,
        lowMode: LowMode.containers,
        lowValue: 1,
      ),
    );
  }

  // all recipe lines of a menu item, archived ones too, oldest first
  Future<List<Map<String, Object?>>> allLines(int menuItemId) {
    return db.query(
      'recipe_lines',
      where: 'menu_item_id = ?',
      whereArgs: [menuItemId],
      orderBy: 'id',
    );
  }

  group('add and list', () {
    test('saves an item and reads it back the same', () async {
      final id = await store.add(
        const MenuItem(
          name: 'Iced Americano (Large)',
          category: 'Coffee',
          priceHint: 140,
        ),
      );
      final item = (await store.list()).single;
      expect(item.id, id);
      expect(item.name, 'Iced Americano (Large)');
      expect(item.category, 'Coffee');
      expect(item.priceHint, 140);
      expect(item.noStock, isFalse);
    });

    test(
      'trims the name, empty category is Other, price is optional',
      () async {
        await store.add(const MenuItem(name: '  Americano ', category: '  '));
        final item = (await store.list()).single;
        expect(item.name, 'Americano');
        expect(item.category, 'Other');
        expect(item.priceHint, isNull);
      },
    );

    test('orders by category, then name, ignoring case', () async {
      await store.add(const MenuItem(name: 'mocha', category: 'Coffee'));
      await store.add(const MenuItem(name: 'French Fries', category: 'Food'));
      await store.add(const MenuItem(name: 'Americano', category: 'coffee'));

      final names = (await store.list()).map((item) => item.name);
      expect(names, ['Americano', 'mocha', 'French Fries']);
      expect(await store.categories(), hasLength(2));
    });

    test('lineCounts counts only active lines per item', () async {
      final latte = await store.add(
        const MenuItem(name: 'Latte (Large)', category: 'Coffee'),
      );
      final tea = await store.add(
        const MenuItem(name: 'Hot tea', category: 'Tea'),
      );
      final milk = await addStock('Whole milk');
      final cream = await addStock('Cream');
      await recipes.addLine(latte, milk, 150);
      final creamLine = await recipes.addLine(latte, cream, 20);
      await recipes.addLine(tea, milk, 30);
      // removed lines are archived, they dont count
      await recipes.removeLine(creamLine);

      expect(await store.lineCounts(), {latte: 1, tea: 1});
    });
  });

  group('rules', () {
    test('name cannot be empty, price cannot be below 0', () async {
      await expectProblem(
        () => store.add(const MenuItem(name: ' ', category: 'Coffee')),
        'Type a name.',
      );
      await expectProblem(
        () => store.add(
          const MenuItem(name: 'Mocha', category: 'Coffee', priceHint: -1),
        ),
        'Price cannot be below 0.',
      );
    });

    test('a used name is refused, an archived one says so', () async {
      final id = await store.add(
        const MenuItem(name: 'Mocha', category: 'Coffee'),
      );
      expect(
        () => store.add(const MenuItem(name: 'MOCHA', category: 'Coffee')),
        throwsA(
          isA<MenuNameTakenException>().having(
            (e) => e.existing.isArchived,
            'archived',
            isFalse,
          ),
        ),
      );

      await store.archive(id);
      expect(
        () => store.add(const MenuItem(name: 'mocha', category: 'Coffee')),
        throwsA(
          isA<MenuNameTakenException>().having(
            (e) => e.existing.isArchived,
            'archived',
            isTrue,
          ),
        ),
      );
    });

    test('no stock only while the recipe is empty', () async {
      // a new item can start as no stock
      await store.add(
        const MenuItem(name: 'Hot water', category: 'Other', noStock: true),
      );

      final milk = await addStock('Milk');
      final id = await store.add(
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      final lineId = await recipes.addLine(id, milk, 150);
      const latte = MenuItem(name: 'Latte', category: 'Coffee', noStock: true);

      await expectProblem(
        () => store.update(
          MenuItem(
            id: id,
            name: latte.name,
            category: latte.category,
            noStock: true,
          ),
        ),
        "Remove the recipe lines first, then tick \"Doesn't use tracked "
        'stock".',
      );

      // archived lines dont count, only active ones
      await recipes.removeLine(lineId);
      await store.update(
        MenuItem(
          id: id,
          name: latte.name,
          category: latte.category,
          noStock: true,
        ),
      );
      expect((await store.findByName('Latte'))!.noStock, isTrue);
    });
  });

  group('archive and restore', () {
    test('archiving archives its active lines at the same time', () async {
      final milk = await addStock('Milk');
      final sugar = await addStock('Syrup');
      final id = await store.add(
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await recipes.addLine(id, milk, 150);
      final oldSugar = await recipes.addLine(id, sugar, 20);
      // an older edit, this line was archived before the item
      now = DateTime.utc(2026, 11, 2);
      await recipes.changeAmount(oldSugar, 25);

      now = DateTime.utc(2026, 11, 3);
      await store.archive(id);

      expect(await store.list(), isEmpty);
      final row = (await db.query(
        'menu_items',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      expect(row['archived_at'], '2026-11-03T00:00:00.000Z');

      final lines = await allLines(id);
      // every line is archived now
      expect(lines.every((line) => line['is_archived'] == 1), isTrue);
      // the old 20 ml line keeps its own older archive time
      expect(lines[1]['archived_at'], '2026-11-02T00:00:00.000Z');
      // milk and the 25 ml line were archived with the item
      expect(lines[0]['archived_at'], '2026-11-03T00:00:00.000Z');
      expect(lines[2]['archived_at'], '2026-11-03T00:00:00.000Z');
    });

    test('restore copies the lines archived with it as new lines', () async {
      final milk = await addStock('Milk');
      final id = await store.add(
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await recipes.addLine(id, milk, 150);

      now = DateTime.utc(2026, 11, 3);
      await store.archive(id);
      now = DateTime.utc(2026, 11, 5);
      final leftOut = await store.restore(id);

      expect(leftOut, isEmpty);
      expect((await store.list()).single.id, id);
      final active = await recipes.lines(id);
      expect(active.single.amount, 150);

      final lines = await allLines(id);
      expect(lines, hasLength(2));
      // the old line stays archived, history is not changed
      expect(lines[0]['is_archived'], 1);
      // the copy is new, made at restore time
      expect(lines[1]['is_archived'], 0);
      expect(lines[1]['created_at'], '2026-11-05T00:00:00.000Z');
    });

    test(
      'restore leaves out lines for stock items archived meanwhile',
      () async {
        final milk = await addStock('Milk');
        final caramel = await addStock('Caramel syrup');
        final id = await store.add(
          const MenuItem(name: 'Caramel latte', category: 'Coffee'),
        );
        await recipes.addLine(id, milk, 150);
        await recipes.addLine(id, caramel, 30);

        await store.archive(id);
        // nothing active uses caramel now, so it can be archived
        await stock.archive(caramel);

        final leftOut = await store.restore(id);
        expect(leftOut, ['Caramel syrup']);
        expect((await recipes.lines(id)).single.stockName, 'Milk');
      },
    );

    test(
      'restore does not bring back lines removed before archiving',
      () async {
        final milk = await addStock('Milk');
        final id = await store.add(
          const MenuItem(name: 'Latte', category: 'Coffee'),
        );
        final lineId = await recipes.addLine(id, milk, 150);
        now = DateTime.utc(2026, 11, 2);
        await recipes.removeLine(lineId);

        now = DateTime.utc(2026, 11, 3);
        await store.archive(id);
        await store.restore(id);

        expect(await recipes.lines(id), isEmpty);
      },
    );
  });
}
