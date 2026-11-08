import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/owner/owner_section_screen.dart';
import 'package:brewmanager/theme/app_theme.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late StockItemStore store;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    store = StockItemStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // shows the owner section and opens the stock items tab
  Future<void> openStockItems(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: OwnerSectionScreen(db: db),
      ),
    );
    await tester.tap(find.text('Stock Items'));
    await tester.pumpAndSettle();
  }

  // saves items before the screen opens
  // runAsync = do real async work (the database) outside the widget test's fake clock
  Future<void> addItems(WidgetTester tester, List<StockItem> items) async {
    await tester.runAsync(() async {
      for (final item in items) {
        await store.add(item);
      }
    });
  }

  testWidgets('owner section has its own tabs and lock and exit', (
    tester,
  ) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: OwnerSectionScreen(db: db),
      ),
    );

    for (final tab in [
      'Analytics',
      'Reports',
      'Menu & Recipes',
      'Stock Items',
      'Settings',
    ]) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('Lock and exit'), findsOneWidget);
  });

  testWidgets('no items yet shows a message', (tester) async {
    await openStockItems(tester);

    expect(find.text('No stock items yet'), findsOneWidget);
    expect(find.text('0 items'), findsOneWidget);
  });

  testWidgets('items show grouped by category with readable values', (
    tester,
  ) async {
    await addItems(tester, [
      const StockItem(
        name: 'Caramel syrup',
        category: 'Syrups',
        baseUnit: BaseUnit.ml,
        countType: CountType.container,
        containerLabel: 'bottle',
        containerSize: 2000,
        lowMode: LowMode.containers,
        lowValue: 1,
      ),
      const StockItem(
        name: 'Fries pack',
        category: 'Food',
        baseUnit: BaseUnit.pcs,
        countType: CountType.number,
        lowMode: LowMode.exact,
        lowValue: 5,
      ),
    ]);
    await openStockItems(tester);

    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('FOOD'), findsOneWidget);
    expect(find.text('SYRUPS'), findsOneWidget);

    expect(find.text('Caramel syrup'), findsOneWidget);
    expect(find.text('bottle · 2,000 ml'), findsOneWidget);
    expect(find.text('1 bottle'), findsOneWidget);

    expect(find.text('Fries pack'), findsOneWidget);
    expect(find.text('Number'), findsOneWidget);
    expect(find.text('5 pcs'), findsOneWidget);

    // food comes before syrups since categories are sorted a-z
    final foodY = tester.getTopLeft(find.text('FOOD')).dy;
    final syrupsY = tester.getTopLeft(find.text('SYRUPS')).dy;
    expect(foodY, lessThan(syrupsY));
  });

  testWidgets('archived items are not in the list', (tester) async {
    await addItems(tester, [
      const StockItem(
        name: 'Old syrup',
        category: 'Syrups',
        baseUnit: BaseUnit.ml,
        countType: CountType.container,
        containerLabel: 'bottle',
        containerSize: 750,
        lowMode: LowMode.exact,
        lowValue: 100,
      ),
    ]);
    await tester.runAsync(() async {
      final id = (await store.findByName('Old syrup'))!.id!;
      await store.archive(id);
    });
    await openStockItems(tester);

    expect(find.text('Old syrup'), findsNothing);
    expect(find.text('No stock items yet'), findsOneWidget);
  });

  group('add / edit panel', () {
    // a normal container item to start tests with
    const syrup = StockItem(
      name: 'Caramel syrup',
      category: 'Syrups',
      baseUnit: BaseUnit.ml,
      countType: CountType.container,
      containerLabel: 'bottle',
      containerSize: 2000,
      lowMode: LowMode.containers,
      lowValue: 1,
    );

    // scrolls the panel to a box and types in it
    Future<void> fill(WidgetTester tester, String key, String value) async {
      final box = find.byKey(Key(key));
      await tester.ensureVisible(box);
      await tester.pumpAndSettle();
      await tester.enterText(box, value);
      await tester.pump();
    }

    Future<void> tapSave(WidgetTester tester) async {
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    Future<void> openAdd(WidgetTester tester) async {
      await openStockItems(tester);
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('Add stock item'), findsOneWidget);
    }

    testWidgets(
      'adds a container item, size typed in L is saved in ml and shown in L',
      (tester) async {
        await openAdd(tester);

        await fill(tester, 'name_field', 'Caramel syrup');
        await fill(tester, 'category_field', 'Syrups');
        await fill(tester, 'label_field', 'bottle');
        await fill(tester, 'size_field', '2');

        // pick L in the size unit picker
        await tester.tap(find.byKey(const Key('size_unit')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('L').last);
        await tester.pumpAndSettle();
        expect(find.text('= 2,000 ml'), findsOneWidget);

        await fill(tester, 'low_field', '1');
        await tapSave(tester);

        // panel closed, full table back with the new row
        expect(find.text('Add stock item'), findsNothing);
        expect(find.text('Saved Caramel syrup.'), findsOneWidget);
        expect(find.text('bottle · 2 L'), findsOneWidget);
        expect(find.text('1 bottle'), findsOneWidget);

        final saved = await tester.runAsync(
          () => store.findByName('Caramel syrup'),
        );
        expect(saved!.containerSize, 2000);
        expect(saved.sizeUnit, 'L');
      },
    );

    testWidgets('an exact low level typed in kg stays kg on screen', (
      tester,
    ) async {
      await openAdd(tester);

      await fill(tester, 'name_field', 'Coffee beans');
      // the form scrolls, so bring each button into view before tapping it
      Future<void> tapVisible(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tapVisible(find.text('g'));
      await fill(tester, 'size_field', '250');
      await tapVisible(find.text('Exact amount'));
      await fill(tester, 'low_field', '1');
      await tester.ensureVisible(find.byKey(const Key('low_unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('low_unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('kg').last);
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(find.text('1 kg'), findsOneWidget);
      final saved = await tester.runAsync(
        () => store.findByName('Coffee beans'),
      );
      // the math still uses grams
      expect(saved!.lowValue, 1000);
      expect(saved.lowUnit, 'kg');

      // opening it again shows 1 with kg picked, not 1000 g
      await tester.tap(find.text('Coffee beans'));
      await tester.pumpAndSettle();
      final low = tester.widget<TextField>(find.byKey(const Key('low_field')));
      expect(low.controller!.text, '1');
      expect(find.text('kg'), findsWidgets);
    });

    testWidgets('number items are pcs with an exact low level', (tester) async {
      await openAdd(tester);

      await tester.tap(find.text('Number'));
      await tester.pumpAndSettle();
      // no size for number items, the name box is the piece name now
      expect(find.text('Piece name (optional)'), findsOneWidget);
      expect(find.byKey(const Key('size_field')), findsNothing);

      await fill(tester, 'name_field', 'Fries pack');
      await fill(tester, 'category_field', 'Food');
      await fill(tester, 'low_field', '5');
      await tapSave(tester);

      expect(find.text('Fries pack'), findsOneWidget);
      expect(find.text('5 pcs'), findsOneWidget);
      final saved = await tester.runAsync(() => store.findByName('Fries pack'));
      expect(saved!.baseUnit, BaseUnit.pcs);
      expect(saved.lowMode, LowMode.exact);
    });

    testWidgets('a number item with a piece name shows it instead of pcs', (
      tester,
    ) async {
      await openAdd(tester);

      await tester.tap(find.text('Number'));
      await tester.pumpAndSettle();
      await fill(tester, 'name_field', 'Fries pack');
      await fill(tester, 'label_field', 'pack');
      expect(find.text('packs'), findsOneWidget);
      await fill(tester, 'low_field', '5');
      await tapSave(tester);

      expect(find.text('5 packs'), findsOneWidget);
      final saved = await tester.runAsync(() => store.findByName('Fries pack'));
      // display only, still pcs
      expect(saved!.baseUnit, BaseUnit.pcs);
      expect(saved.containerLabel, 'pack');
    });

    testWidgets('saving with a broken rule shows the problem', (tester) async {
      await openAdd(tester);
      await tapSave(tester);

      expect(find.text('Type the container size as a number.'), findsOneWidget);

      await fill(tester, 'size_field', '750');
      await tapSave(tester);
      expect(find.text('Type a name.'), findsOneWidget);
      // still on the panel, nothing saved
      expect(find.text('Add stock item'), findsOneWidget);
    });

    testWidgets('a name of an archived item offers restore', (tester) async {
      await addItems(tester, [syrup]);
      await tester.runAsync(() async {
        final id = (await store.findByName('Caramel syrup'))!.id!;
        await store.archive(id);
      });
      await openAdd(tester);

      await fill(tester, 'name_field', 'caramel SYRUP');
      await fill(tester, 'category_field', 'Syrups');
      await fill(tester, 'label_field', 'bottle');
      await fill(tester, 'size_field', '1000');
      await tapSave(tester);

      final restore = find.text('Restore it');
      await tester.ensureVisible(restore);
      await tester.pumpAndSettle();
      await tester.tap(restore);
      await tester.pumpAndSettle();

      expect(find.text('Restored Caramel syrup.'), findsOneWidget);
      // back with its old settings, not the 1000 typed
      expect(find.text('bottle · 2,000 ml'), findsOneWidget);
    });

    testWidgets('tapping a row edits it', (tester) async {
      await addItems(tester, [syrup]);
      await openStockItems(tester);

      await tester.tap(find.text('Caramel syrup'));
      await tester.pumpAndSettle();
      expect(find.text('Edit stock item'), findsOneWidget);

      await fill(tester, 'name_field', 'Caramel sauce');
      await tapSave(tester);

      expect(find.text('Caramel sauce'), findsOneWidget);
      expect(find.text('Caramel syrup'), findsNothing);
    });

    testWidgets('a used item shows unit and count type locked', (tester) async {
      await addItems(tester, [syrup]);
      // put it in a recipe so it counts as used
      await tester.runAsync(() async {
        final id = (await store.findByName('Caramel syrup'))!.id!;
        final menuId = await db.insert('menu_items', {
          'name': 'Caramel latte',
          'category': 'Coffee',
        });
        await db.insert('recipe_lines', {
          'menu_item_id': menuId,
          'stock_item_id': id,
          'amount': 30,
          'created_at': DateTime.utc(2026, 11, 1).toIso8601String(),
        });
      });
      await openStockItems(tester);

      await tester.tap(find.text('Caramel syrup'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Unit and count type are locked'),
        findsOneWidget,
      );
      // SegmentedButton with no onSelectionChanged = greyed out
      final unitButtons = tester.widget<SegmentedButton<BaseUnit>>(
        find.byType(SegmentedButton<BaseUnit>),
      );
      expect(unitButtons.onSelectionChanged, isNull);
    });

    testWidgets('adding has no archive button', (tester) async {
      await openAdd(tester);
      expect(find.widgetWithText(TextButton, 'Archive'), findsNothing);
    });

    testWidgets('archive asks first, then hides the row', (tester) async {
      await addItems(tester, [syrup]);
      await openStockItems(tester);
      await tester.tap(find.text('Caramel syrup'));
      await tester.pumpAndSettle();

      // runAsync since the button reads the db before the dialog shows
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(TextButton, 'Archive'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Archive Caramel syrup?'), findsOneWidget);

      // the archive button inside the dialog
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.text('Archived Caramel syrup.'), findsOneWidget);
      expect(find.text('No stock items yet'), findsOneWidget);
    });

    testWidgets('archive is blocked while a recipe uses the item', (
      tester,
    ) async {
      await addItems(tester, [syrup]);
      await tester.runAsync(() async {
        final id = (await store.findByName('Caramel syrup'))!.id!;
        final menuId = await db.insert('menu_items', {
          'name': 'Caramel latte',
          'category': 'Coffee',
        });
        await db.insert('recipe_lines', {
          'menu_item_id': menuId,
          'stock_item_id': id,
          'amount': 30,
          'created_at': DateTime.utc(2026, 11, 1).toIso8601String(),
        });
      });
      await openStockItems(tester);
      await tester.tap(find.text('Caramel syrup'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(TextButton, 'Archive'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Can't archive Caramel syrup. It's used in: "),
        findsOneWidget,
      );
      // no dialog, still on the edit panel
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit stock item'), findsOneWidget);
    });

    testWidgets('archived view shows the item, restore brings it back', (
      tester,
    ) async {
      await addItems(tester, [syrup]);
      await tester.runAsync(() async {
        final id = (await store.findByName('Caramel syrup'))!.id!;
        await store.archive(id);
      });
      await openStockItems(tester);
      expect(find.text('No stock items yet'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Archived'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('1 archived'), findsOneWidget);
      // no adding in the archived view
      expect(find.text('Add item'), findsNothing);

      await tester.tap(find.text('Caramel syrup'));
      await tester.pumpAndSettle();
      expect(find.text('Archived item'), findsOneWidget);
      expect(find.text('Save'), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.text('Restore'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Restored Caramel syrup.'), findsOneWidget);
      expect(find.text('No archived items'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Active'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Caramel syrup'), findsOneWidget);
    });

    testWidgets('category chips fill the category box', (tester) async {
      await addItems(tester, [syrup]);
      await openAdd(tester);

      await tester.tap(find.widgetWithText(ActionChip, 'Syrups'));
      await tester.pump();

      final box = tester.widget<TextField>(
        find.byKey(const Key('category_field')),
      );
      expect(box.controller!.text, 'Syrups');
    });
  });
}
