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
  late RecipeStore recipes;
  late MenuItemStore menu;
  late StockItemStore stock;
  // fake clock, tests move it forward to get known times
  late DateTime now;
  late int latte;
  late int milk;

  // defined before setUp since setUp uses it
  Future<int> addStock(String name, {BaseUnit unit = BaseUnit.ml}) {
    return stock.add(
      StockItem(
        name: name,
        category: 'Dairy',
        baseUnit: unit,
        countType: CountType.container,
        containerSize: 1000,
        lowMode: LowMode.containers,
        lowValue: 1,
      ),
    );
  }

  setUp(() async {
    db = await openTestDatabase();
    now = DateTime.utc(2026, 11, 1, 8);
    recipes = RecipeStore(db, clock: () => now);
    menu = MenuItemStore(db, clock: () => now);
    stock = StockItemStore(db);
    latte = await menu.add(
      const MenuItem(name: 'Spanish Latte (Large)', category: 'Coffee'),
    );
    milk = await addStock('Whole milk');
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> expectProblem(Future<void> Function() save, String message) {
    return expectLater(
      save,
      throwsA(
        isA<MenuItemException>().having((e) => e.message, 'message', message),
      ),
    );
  }

  // the same query the recalculation will use (rule 12): the lines active at that time
  Future<List<double>> amountsAt(String time) async {
    final rows = await db.rawQuery(
      '''
      SELECT amount FROM recipe_lines
      WHERE menu_item_id = ?
        AND created_at <= ?
        AND (archived_at IS NULL OR archived_at > ?)
      ''',
      [latte, time, time],
    );
    return rows.map((row) => (row['amount'] as num).toDouble()).toList();
  }

  test('lines come back a-z with the stock name and unit', () async {
    final beans = await addStock('Espresso beans', unit: BaseUnit.g);
    await recipes.addLine(latte, milk, 150);
    await recipes.addLine(latte, beans, 18);

    final lines = await recipes.lines(latte);
    expect(lines.map((line) => line.stockName), [
      'Espresso beans',
      'Whole milk',
    ]);
    expect(lines.first.baseUnit, BaseUnit.g);
    expect(lines.first.amount, 18);
  });

  group('add rules', () {
    test('amount must be more than 0', () async {
      await expectProblem(
        () => recipes.addLine(latte, milk, 0),
        'Amount must be more than 0.',
      );
    });

    test('a stock item only once per recipe', () async {
      await recipes.addLine(latte, milk, 150);
      await expectProblem(
        () => recipes.addLine(latte, milk, 180),
        'Whole milk is already in this recipe. Change its amount instead.',
      );
    });

    test('archived stock items cannot be added', () async {
      await stock.archive(milk);
      await expectProblem(
        () => recipes.addLine(latte, milk, 150),
        'Whole milk is archived. Restore it first.',
      );
    });

    test('no stock and archived menu items get no lines', () async {
      final water = await menu.add(
        const MenuItem(name: 'Hot water', category: 'Other', noStock: true),
      );
      await expectProblem(
        () => recipes.addLine(water, milk, 150),
        "Untick \"Doesn't use tracked stock\" before adding to the recipe.",
      );

      await menu.archive(latte);
      await expectProblem(
        () => recipes.addLine(latte, milk, 150),
        'Restore this menu item before changing its recipe.',
      );
    });
  });

  group('change and remove', () {
    test('changing an amount archives the old line and adds a new one', () async {
      final oldId = await recipes.addLine(latte, milk, 150);

      now = DateTime.utc(2026, 11, 3, 8);
      final newId = await recipes.changeAmount(oldId, 180);

      expect(newId, isNot(oldId));
      expect((await recipes.lines(latte)).single.amount, 180);

      // a day submitted before the edit uses 150, at or after it uses 180, never both
      expect(await amountsAt('2026-11-02T10:00:00.000Z'), [150]);
      expect(await amountsAt('2026-11-03T08:00:00.000Z'), [180]);
      expect(await amountsAt('2026-11-04T10:00:00.000Z'), [180]);
    });

    test('same amount makes no new line', () async {
      final id = await recipes.addLine(latte, milk, 150);
      expect(await recipes.changeAmount(id, 150), id);
      final count = await db.query('recipe_lines');
      expect(count, hasLength(1));
    });

    test('removing archives the line, the stock item stays locked', () async {
      final id = await recipes.addLine(latte, milk, 150);
      await recipes.removeLine(id);

      expect(await recipes.lines(latte), isEmpty);
      // still in the db for old reports
      final row = (await db.query('recipe_lines')).single;
      expect(row['is_archived'], 1);
      // archived recipe lines still lock the unit (rule 1)
      expect(await stock.isUsed(milk), isTrue);
      // but they dont block archiving the stock item (rule 12)
      expect(await stock.archiveProblem(milk), isNull);
    });
  });
}
