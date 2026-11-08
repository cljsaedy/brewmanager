import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/units.dart';

import '../helpers/test_database.dart';

// a normal container item, tests change what they need with copyWith
StockItem syrup({String name = 'Caramel syrup', String category = 'Syrups'}) {
  return StockItem(
    name: name,
    category: category,
    baseUnit: BaseUnit.ml,
    countType: CountType.container,
    containerLabel: 'bottle',
    containerSize: 2000,
    lowMode: LowMode.containers,
    lowValue: 1,
  );
}

// a normal number item
StockItem friesPack() {
  return const StockItem(
    name: 'Fries pack',
    category: 'Food',
    baseUnit: BaseUnit.pcs,
    countType: CountType.number,
    lowMode: LowMode.exact,
    lowValue: 5,
  );
}

void main() {
  late Database db;
  late StockItemStore store;

  setUp(() async {
    db = await openTestDatabase();
    store = StockItemStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // checks that saving fails with this plain words message
  Future<void> expectProblem(Future<void> Function() save, String message) {
    return expectLater(
      save,
      throwsA(
        isA<StockItemException>().having((e) => e.message, 'message', message),
      ),
    );
  }

  group('add and list', () {
    test('saves an item and reads it back the same', () async {
      final id = await store.add(syrup());
      final items = await store.list();

      expect(items, hasLength(1));
      final item = items.single;
      expect(item.id, id);
      expect(item.name, 'Caramel syrup');
      expect(item.baseUnit, BaseUnit.ml);
      expect(item.countType, CountType.container);
      expect(item.containerLabel, 'bottle');
      expect(item.containerSize, 2000);
      expect(item.lowMode, LowMode.containers);
      expect(item.lowValue, 1);
      expect(item.isArchived, isFalse);
    });

    test('trims spaces off the name and category', () async {
      await store.add(syrup(name: '  Vanilla syrup ', category: ' Syrups  '));
      final item = (await store.list()).single;

      expect(item.name, 'Vanilla syrup');
      expect(item.category, 'Syrups');
    });

    test('orders by category, then name, ignoring case', () async {
      await store.add(syrup(name: 'vanilla syrup', category: 'Syrups'));
      await store.add(syrup(name: 'Caramel syrup', category: 'syrups'));
      await store.add(syrup(name: 'Whole milk', category: 'Milk'));

      final names = (await store.list()).map((item) => item.name).toList();
      expect(names, ['Whole milk', 'Caramel syrup', 'vanilla syrup']);
    });

    test(
      'number items keep the label as a piece name but never a size',
      () async {
        await store.add(
          friesPack().copyWith(containerLabel: ' box ', containerSize: 10),
        );
        final item = (await store.list()).single;

        expect(item.containerLabel, 'box');
        expect(item.containerSize, isNull);
        expect(item.baseUnit, BaseUnit.pcs);
      },
    );

    test('typed units are saved, the base unit is saved as null', () async {
      await store.add(
        syrup().copyWith(
          sizeUnit: 'L',
          lowMode: LowMode.exact,
          lowValue: 500,
          lowUnit: 'ml',
        ),
      );
      final item = (await store.list()).single;

      expect(item.sizeUnit, 'L');
      expect(item.lowUnit, isNull);
    });

    test('a low unit is dropped in containers mode', () async {
      await store.add(syrup().copyWith(lowUnit: 'L'));

      expect((await store.list()).single.lowUnit, isNull);
    });

    test('a unit that does not fit the base unit is refused', () async {
      expect(
        () => store.add(syrup().copyWith(sizeUnit: 'kg')),
        throwsA(isA<StockItemException>()),
      );
    });

    test('categories gives each used category once', () async {
      await store.add(syrup(name: 'Caramel syrup'));
      // different case is still the same category
      await store.add(syrup(name: 'Vanilla syrup', category: 'syrups'));
      await store.add(friesPack());

      expect(await store.categories(), hasLength(2));
      expect(await store.categories(), contains('Food'));
    });
  });

  group('rules', () {
    test('name cannot be empty', () async {
      await expectProblem(() => store.add(syrup(name: '   ')), 'Type a name.');
    });

    test('empty category is saved as Other', () async {
      await store.add(syrup(category: '  '));
      final item = await store.findByName('Caramel syrup');
      expect(item!.category, 'Other');
    });

    test(
      'empty container label is saved as null and shows container',
      () async {
        await store.add(syrup().copyWith(containerLabel: ' '));
        final item = await store.findByName('Caramel syrup');
        expect(item!.containerLabel, isNull);
        expect(item.containerName, 'container');
      },
    );

    test('container items need a size above 0', () async {
      await expectProblem(
        () => store.add(syrup().copyWith(containerSize: 0)),
        'Container size must be more than 0.',
      );
    });

    test('number items are pcs only, with an exact low-stock level', () async {
      await expectProblem(
        () => store.add(friesPack().copyWith(baseUnit: BaseUnit.g)),
        'Number items are counted in pcs.',
      );
      await expectProblem(
        () => store.add(friesPack().copyWith(lowMode: LowMode.containers)),
        'Number items need an exact low-stock level.',
      );
    });

    test('low-stock level cannot be below 0', () async {
      await expectProblem(
        () => store.add(syrup().copyWith(lowValue: -1)),
        'Low-stock level cannot be below 0.',
      );
    });

    test('nothing is saved when a rule is broken', () async {
      await expectLater(
        () => store.add(syrup(name: '')),
        throwsA(isA<StockItemException>()),
      );
      expect(await store.list(), isEmpty);
    });
  });

  group('names', () {
    test('a used name is refused, ignoring case and spaces', () async {
      await store.add(syrup(name: 'Caramel syrup'));

      await expectLater(
        () => store.add(syrup(name: '  CARAMEL SYRUP ')),
        throwsA(
          isA<NameTakenException>().having(
            (e) => e.existing.isArchived,
            'existing.isArchived',
            isFalse,
          ),
        ),
      );
    });

    test('a name of an archived item says so, to offer restore', () async {
      final id = await store.add(syrup(name: 'Caramel syrup'));
      await store.archive(id);

      await expectLater(
        () => store.add(syrup(name: 'caramel syrup')),
        throwsA(
          isA<NameTakenException>()
              .having((e) => e.existing.id, 'existing.id', id)
              .having((e) => e.existing.isArchived, 'isArchived', isTrue),
        ),
      );
    });

    test('editing can keep its own name but not take another', () async {
      final caramelId = await store.add(syrup(name: 'Caramel syrup'));
      await store.add(syrup(name: 'Vanilla syrup'));
      final caramel = (await store.list()).firstWhere((i) => i.id == caramelId);

      // same name, only the size changed, that is fine
      await store.update(caramel.copyWith(containerSize: 1000));

      await expectLater(
        () => store.update(caramel.copyWith(name: 'vanilla SYRUP')),
        throwsA(isA<NameTakenException>()),
      );
    });
  });

  group('archive and restore', () {
    test('archived items move to the archived list and back', () async {
      final id = await store.add(syrup());

      await store.archive(id);
      expect(await store.list(), isEmpty);
      expect((await store.list(archived: true)).single.isArchived, isTrue);
      // archived categories dont show as suggestions
      expect(await store.categories(), isEmpty);

      await store.restore(id);
      expect((await store.list()).single.id, id);
      expect(await store.list(archived: true), isEmpty);
    });

    test('a restore marks the item for an opening count', () async {
      final id = await store.add(syrup());
      expect((await store.list()).single.needsOpeningCount, isFalse);

      await store.archive(id);
      await store.restore(id);
      expect((await store.list()).single.needsOpeningCount, isTrue);
    });

    test('editing a restored item keeps the mark', () async {
      final id = await store.add(syrup());
      await store.archive(id);
      await store.restore(id);

      final item = (await store.list()).single;
      await store.update(item.copyWith(lowValue: 3));
      expect((await store.list()).single.needsOpeningCount, isTrue);
    });

    // adds these menu items, each with a recipe line using the stock item
    // archived = true puts in archived recipe lines (old amounts kept for reports)
    Future<void> addRecipes(
      int stockItemId,
      List<String> menuNames, {
      bool archived = false,
    }) async {
      for (final name in menuNames) {
        final menuId = await db.insert('menu_items', {
          'name': name,
          'category': 'Coffee',
        });
        await db.insert('recipe_lines', {
          'menu_item_id': menuId,
          'stock_item_id': stockItemId,
          'amount': 30,
          'created_at': DateTime.utc(2026, 11, 1).toIso8601String(),
          'is_archived': archived ? 1 : 0,
          'archived_at': archived
              ? DateTime.utc(2026, 11, 2).toIso8601String()
              : null,
        });
      }
    }

    test('cannot archive while an active recipe uses it', () async {
      final id = await store.add(syrup());
      // added out of order on purpose, the message lists them a-z
      await addRecipes(id, ['Iced caramel', 'Caramel latte (Large)']);

      const message =
          "Can't archive Caramel syrup. It's used in: "
          'Caramel latte (Large), Iced caramel. '
          'Remove or replace it in those recipes first.';
      expect(await store.archiveProblem(id), message);
      await expectProblem(() => store.archive(id), message);
      // still active
      expect((await store.list()).single.id, id);
    });

    test('archived recipe lines do not block archiving', () async {
      final id = await store.add(syrup());
      await addRecipes(id, ['Caramel latte (Large)'], archived: true);

      expect(await store.archiveProblem(id), isNull);
      await store.archive(id);
      expect(await store.list(), isEmpty);
    });
  });

  group('lock after first use', () {
    // adds a menu item with a recipe line using the stock item
    Future<void> useInRecipe(int stockItemId) async {
      final menuId = await db.insert('menu_items', {
        'name': 'Caramel latte (Large)',
        'category': 'Coffee',
      });
      await db.insert('recipe_lines', {
        'menu_item_id': menuId,
        'stock_item_id': stockItemId,
        'amount': 30,
        'created_at': DateTime.utc(2026, 11, 1).toIso8601String(),
      });
    }

    // adds a count line for the item on a day with this status
    Future<void> useInCount(int stockItemId, String status) async {
      final dayId = await db.insert('business_days', {
        'business_date': '2026-11-01',
        'status': status,
      });
      await db.insert('count_lines', {
        'day_id': dayId,
        'stock_item_id': stockItemId,
      });
    }

    Future<StockItem> getItem(int id) async =>
        (await store.list()).firstWhere((item) => item.id == id);

    test('a new item is not used, everything can change', () async {
      final id = await store.add(syrup());
      expect(await store.isUsed(id), isFalse);

      await store.update((await getItem(id)).copyWith(baseUnit: BaseUnit.g));
      expect((await getItem(id)).baseUnit, BaseUnit.g);
    });

    test('after a recipe uses it, unit and count type are locked', () async {
      final id = await store.add(syrup());
      await useInRecipe(id);
      final item = await getItem(id);

      expect(await store.isUsed(id), isTrue);
      await expectLater(
        () => store.update(item.copyWith(baseUnit: BaseUnit.g)),
        throwsA(isA<StockItemException>()),
      );
      await expectLater(
        () => store.update(
          item.copyWith(
            countType: CountType.number,
            baseUnit: BaseUnit.pcs,
            lowMode: LowMode.exact,
          ),
        ),
        throwsA(isA<StockItemException>()),
      );
      expect((await getItem(id)).baseUnit, BaseUnit.ml);
    });

    test('a used item can still change size, name and low level', () async {
      final id = await store.add(syrup());
      await useInRecipe(id);

      await store.update(
        (await getItem(
          id,
        )).copyWith(name: 'Caramel sauce', containerSize: 1000, lowValue: 2),
      );
      final item = await getItem(id);
      expect(item.name, 'Caramel sauce');
      expect(item.containerSize, 1000);
      expect(item.lowValue, 2);
    });

    test('a submitted count locks it, a draft count does not', () async {
      final draftId = await store.add(syrup(name: 'Caramel syrup'));
      await useInCount(draftId, 'draft');
      expect(await store.isUsed(draftId), isFalse);

      await db.delete('count_lines');
      await db.delete('business_days');

      final submittedId = await store.add(syrup(name: 'Vanilla syrup'));
      await useInCount(submittedId, 'submitted');
      expect(await store.isUsed(submittedId), isTrue);
    });
  });
}
