import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/owner/owner_section_screen.dart';
import 'package:brewmanager/theme/app_theme.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late MenuItemStore store;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    store = MenuItemStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // shows the owner section and opens the menu & recipes tab
  Future<void> openMenu(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: OwnerSectionScreen(db: db),
      ),
    );
    // the rail button, the tab title also says menu & recipes once it is open
    await tester.tap(find.text('Menu & Recipes').first);
    await tester.pumpAndSettle();
  }

  // runAsync = do real async work (the database) outside the widget test's fake clock
  Future<int> addItem(WidgetTester tester, MenuItem item) async {
    return (await tester.runAsync(() => store.add(item)))!;
  }

  // adds a stock item and puts it in the menu item's recipe
  Future<void> addRecipeLine(WidgetTester tester, int menuItemId) async {
    await tester.runAsync(() async {
      final milk = await StockItemStore(db).add(
        const StockItem(
          name: 'Whole milk',
          category: 'Dairy',
          baseUnit: BaseUnit.ml,
          countType: CountType.container,
          containerSize: 1000,
          lowMode: LowMode.containers,
          lowValue: 1,
        ),
      );
      await RecipeStore(db).addLine(menuItemId, milk, 150);
    });
  }

  // the screens read the db after a tap, so give it real time
  Future<void> waitForDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  // scrolls the panel to it and taps it, the recipe sits below the fields
  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
  }

  // puts a stock item that is already saved in the recipe
  Future<void> addRecipeLineFor(
    WidgetTester tester,
    int menuItemId,
    String stockName,
    double amount,
  ) async {
    await tester.runAsync(() async {
      final stock = await StockItemStore(db).findByName(stockName);
      await RecipeStore(db).addLine(menuItemId, stock!.id!, amount);
    });
  }

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
    await openMenu(tester);
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Add menu item'), findsOneWidget);
  }

  testWidgets('no items yet shows a message', (tester) async {
    await openMenu(tester);

    expect(find.text('No menu items yet'), findsOneWidget);
    expect(find.text('0 menu items'), findsOneWidget);
  });

  testWidgets('items show grouped by category with price and recipe', (
    tester,
  ) async {
    final latte = await addItem(
      tester,
      const MenuItem(
        name: 'Spanish Latte (Large)',
        category: 'Coffee',
        priceHint: 1500,
      ),
    );
    await addItem(
      tester,
      const MenuItem(name: 'Americano', category: 'Coffee'),
    );
    await addItem(
      tester,
      const MenuItem(name: 'Hot water', category: '', noStock: true),
    );
    await addRecipeLine(tester, latte);
    await openMenu(tester);

    expect(find.text('3 menu items'), findsOneWidget);
    expect(find.text('COFFEE'), findsOneWidget);
    // empty category was saved as Other
    expect(find.text('OTHER'), findsOneWidget);
    expect(find.text('1,500'), findsOneWidget);
    expect(find.text('1 stock item'), findsOneWidget);
    expect(find.text('No recipe yet'), findsOneWidget);
    expect(find.text('Not compared'), findsOneWidget);
  });

  testWidgets('adds an item, chip fills the category, price is saved', (
    tester,
  ) async {
    await addItem(
      tester,
      const MenuItem(name: 'Americano', category: 'Coffee'),
    );
    await openAdd(tester);

    await fill(tester, 'menu_name_field', 'Iced Americano (Large)');
    final chip = find.widgetWithText(ActionChip, 'Coffee');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pump();
    await fill(tester, 'menu_price_field', '1,250.50');
    await tapSave(tester);

    // the panel stays open on the new item, ready for its recipe
    expect(find.text('Edit menu item'), findsOneWidget);
    expect(find.text('Saved Iced Americano (Large).'), findsOneWidget);
    // once in the table, once in the name box
    expect(find.text('Iced Americano (Large)'), findsNWidgets(2));

    final saved = await tester.runAsync(
      () => store.findByName('Iced Americano (Large)'),
    );
    expect(saved!.category, 'Coffee');
    expect(saved.priceHint, 1250.5);
  });

  testWidgets('a wrong price or empty name shows the problem', (tester) async {
    await openAdd(tester);

    await fill(tester, 'menu_price_field', 'abc');
    await tapSave(tester);
    expect(find.text('Type the price as a number.'), findsOneWidget);

    await fill(tester, 'menu_price_field', '');
    await tapSave(tester);
    expect(find.text('Type a name.'), findsOneWidget);
    // still on the panel, nothing saved
    expect(find.text('Add menu item'), findsOneWidget);
  });

  testWidgets('tapping a row edits it, an empty price clears it', (
    tester,
  ) async {
    await addItem(
      tester,
      const MenuItem(name: 'Americano', category: 'Coffee', priceHint: 100),
    );
    await openMenu(tester);

    await tester.tap(find.text('Americano'));
    await tester.pumpAndSettle();
    expect(find.text('Edit menu item'), findsOneWidget);

    await fill(tester, 'menu_name_field', 'Hot Americano');
    await fill(tester, 'menu_price_field', '');
    await tapSave(tester);

    expect(find.text('Hot Americano'), findsOneWidget);
    final saved = await tester.runAsync(
      () => store.findByName('Hot Americano'),
    );
    expect(saved!.priceHint, isNull);
  });

  testWidgets('no stock box is greyed out while the item has a recipe', (
    tester,
  ) async {
    final latte = await addItem(
      tester,
      const MenuItem(name: 'Latte', category: 'Coffee'),
    );
    await addRecipeLine(tester, latte);
    await openMenu(tester);

    await tester.tap(find.text('Latte'));
    // the line count is read from the db after the panel opens
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    final box = tester.widget<CheckboxListTile>(
      find.byKey(const Key('no_stock_box')),
    );
    expect(box.onChanged, isNull);
    expect(
      find.text('Remove the recipe lines first to tick this.'),
      findsOneWidget,
    );
  });

  testWidgets('no stock box can be ticked on a new item', (tester) async {
    await openAdd(tester);

    await fill(tester, 'menu_name_field', 'Hot water');
    await tapVisible(tester, find.byKey(const Key('no_stock_box')));
    await tester.pump();
    await tapSave(tester);

    expect(find.text('Not compared'), findsOneWidget);
  });

  group('recipe', () {
    // saved menu item + stock items, each in the unit it is counted in
    const milk = StockItem(
      name: 'Whole milk',
      category: 'Dairy',
      baseUnit: BaseUnit.ml,
      countType: CountType.container,
      containerSize: 1000,
      lowMode: LowMode.containers,
      lowValue: 1,
    );
    const beans = StockItem(
      name: 'Espresso beans',
      category: 'Coffee',
      baseUnit: BaseUnit.g,
      countType: CountType.container,
      containerSize: 250,
      lowMode: LowMode.containers,
      lowValue: 1,
    );

    Future<void> addStock(WidgetTester tester, List<StockItem> items) async {
      await tester.runAsync(() async {
        for (final item in items) {
          await StockItemStore(db).add(item);
        }
      });
    }

    // opens the panel of the item, with its recipe loaded
    Future<void> openItem(WidgetTester tester, String name) async {
      await openMenu(tester);
      await tester.tap(find.text(name));
      await waitForDb(tester);
    }

    // picks a stock item in the dropdown
    Future<void> pickStock(WidgetTester tester, String name) async {
      final picker = find.byKey(const Key('recipe_stock_picker'));
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    // taps add or update and waits for the db
    Future<void> tapButton(WidgetTester tester, String label) async {
      final button = find.widgetWithText(OutlinedButton, label);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await waitForDb(tester);
    }

    Future<List<RecipeLine>> savedLines(WidgetTester tester, int id) async {
      return (await tester.runAsync(() => RecipeStore(db).lines(id)))!;
    }

    testWidgets('a new item stays open after saving, ready for its recipe', (
      tester,
    ) async {
      await addStock(tester, [milk]);
      await openAdd(tester);
      expect(find.text('Save this item to add its recipe.'), findsOneWidget);

      await fill(tester, 'menu_name_field', 'Latte');
      await tapSave(tester);
      await waitForDb(tester);

      expect(find.text('Edit menu item'), findsOneWidget);
      expect(find.text('No lines yet.'), findsOneWidget);
      expect(find.text('Saved Latte.'), findsOneWidget);
    });

    testWidgets('adds a line, the table count follows right away', (
      tester,
    ) async {
      await addStock(tester, [milk]);
      final latte = await addItem(
        tester,
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await openItem(tester, 'Latte');
      expect(find.text('No recipe yet'), findsOneWidget);

      await pickStock(tester, 'Whole milk');
      await fill(tester, 'recipe_amount_field', '150');
      await tapButton(tester, 'Add');

      expect(find.text('150 ml'), findsOneWidget);
      expect(find.text('1 stock item'), findsOneWidget);
      // the only stock item is used now, so nothing is left to pick
      expect(
        find.text('Every stock item is already in this recipe.'),
        findsOneWidget,
      );
      expect((await savedLines(tester, latte)).single.amount, 150);
    });

    testWidgets('amount typed in oz is saved in ml', (tester) async {
      await addStock(tester, [milk]);
      final latte = await addItem(
        tester,
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await openItem(tester, 'Latte');

      await pickStock(tester, 'Whole milk');
      await fill(tester, 'recipe_amount_field', '2');
      final unit = find.byKey(const Key('recipe_amount_unit'));
      await tester.ensureVisible(unit);
      await tester.pumpAndSettle();
      await tester.tap(unit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('oz').last);
      await tester.pumpAndSettle();
      expect(find.text('= 59.15 ml'), findsOneWidget);

      await tapButton(tester, 'Add');
      expect((await savedLines(tester, latte)).single.amount, 59.147);
      // both show, so what was typed stays in sight
      expect(find.text('2 oz (59.15 ml)'), findsOneWidget);

      // tapping the line opens it in the unit it was typed in
      await tapVisible(tester, find.text('2 oz (59.15 ml)'));
      await tester.pumpAndSettle();
      final box = tester.widget<TextField>(
        find.byKey(const Key('recipe_amount_field')),
      );
      expect(box.controller!.text, '2');
      expect(find.text('oz'), findsWidgets);
    });

    testWidgets('a decimal amount like 2.96 g is saved and shown', (
      tester,
    ) async {
      await addStock(tester, [beans]);
      final latte = await addItem(
        tester,
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await openItem(tester, 'Latte');

      await pickStock(tester, 'Espresso beans');
      await fill(tester, 'recipe_amount_field', '2.96');
      await tapButton(tester, 'Add');

      expect(find.text('2.96 g'), findsOneWidget);
      expect((await savedLines(tester, latte)).single.amount, 2.96);
    });

    testWidgets('a g item only offers weight units', (tester) async {
      await addStock(tester, [beans]);
      await addItem(tester, const MenuItem(name: 'Latte', category: 'Coffee'));
      await openItem(tester, 'Latte');

      await pickStock(tester, 'Espresso beans');
      final unit = find.byKey(const Key('recipe_amount_unit'));
      await tester.ensureVisible(unit);
      await tester.pumpAndSettle();
      await tester.tap(unit);
      await tester.pumpAndSettle();

      expect(find.text('kg'), findsWidgets);
      expect(find.text('ml'), findsNothing);
      expect(find.text('oz'), findsNothing);
    });

    testWidgets('a wrong amount shows the problem', (tester) async {
      await addStock(tester, [milk]);
      final latte = await addItem(
        tester,
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await openItem(tester, 'Latte');

      await pickStock(tester, 'Whole milk');
      await fill(tester, 'recipe_amount_field', 'abc');
      await tapButton(tester, 'Add');
      expect(find.text('Type the amount as a number.'), findsOneWidget);

      await fill(tester, 'recipe_amount_field', '0');
      await tapButton(tester, 'Add');
      expect(find.text('Amount must be more than 0.'), findsOneWidget);
      expect(await savedLines(tester, latte), isEmpty);
    });

    testWidgets('tapping a line changes its amount, the rule 12 way', (
      tester,
    ) async {
      await addStock(tester, [milk]);
      final latte = await addItem(
        tester,
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await addRecipeLineFor(tester, latte, 'Whole milk', 150);
      await openItem(tester, 'Latte');

      await tapVisible(tester, find.text('150 ml'));
      await tester.pumpAndSettle();
      expect(find.text('Change Whole milk'), findsOneWidget);

      await fill(tester, 'recipe_amount_field', '180');
      await tapButton(tester, 'Update');

      expect(find.text('180 ml'), findsOneWidget);
      expect((await savedLines(tester, latte)).single.amount, 180);
      // the old line is still there, archived, for old days
      final rows = await tester.runAsync(() => db.query('recipe_lines'));
      expect(rows, hasLength(2));
    });

    testWidgets('removing a line frees the no stock box', (tester) async {
      await addStock(tester, [milk]);
      final latte = await addItem(
        tester,
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await addRecipeLineFor(tester, latte, 'Whole milk', 150);
      await openItem(tester, 'Latte');

      await tapVisible(tester, find.byTooltip('Remove Whole milk'));
      await waitForDb(tester);

      expect(find.text('No lines yet.'), findsOneWidget);
      expect(find.text('No recipe yet'), findsOneWidget);
      final box = tester.widget<CheckboxListTile>(
        find.byKey(const Key('no_stock_box')),
      );
      expect(box.onChanged, isNotNull);
    });

    testWidgets('archived stock items are not in the picker', (tester) async {
      await addStock(tester, [milk, beans]);
      await tester.runAsync(() async {
        final store = StockItemStore(db);
        await store.archive((await store.findByName('Whole milk'))!.id!);
      });
      await addItem(tester, const MenuItem(name: 'Latte', category: 'Coffee'));
      await openItem(tester, 'Latte');

      final picker = find.byKey(const Key('recipe_stock_picker'));
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();

      expect(find.text('Espresso beans'), findsWidgets);
      expect(find.text('Whole milk'), findsNothing);
    });

    testWidgets('ticking no stock hides the recipe, unticking asks to save', (
      tester,
    ) async {
      await addStock(tester, [milk]);
      await addItem(
        tester,
        const MenuItem(name: 'Hot water', category: '', noStock: true),
      );
      await openItem(tester, 'Hot water');
      expect(find.text('Save this item to add its recipe.'), findsNothing);

      await tapVisible(tester, find.byKey(const Key('no_stock_box')));
      await tester.pump();
      expect(find.text('Save this item to add its recipe.'), findsOneWidget);

      await tapSave(tester);
      await waitForDb(tester);
      // stays open, now the recipe can be added
      expect(find.text('No lines yet.'), findsOneWidget);
    });

    testWidgets('with no stock items it says to add them first', (
      tester,
    ) async {
      await addItem(tester, const MenuItem(name: 'Latte', category: 'Coffee'));
      await openItem(tester, 'Latte');

      expect(
        find.text('Add stock items first, in the Stock Items tab.'),
        findsOneWidget,
      );
    });
  });

  group('archive and restore', () {
    const milk = StockItem(
      name: 'Whole milk',
      category: 'Dairy',
      baseUnit: BaseUnit.ml,
      countType: CountType.container,
      containerSize: 1000,
      lowMode: LowMode.containers,
      lowValue: 1,
    );

    // a menu item with one recipe line, typed in oz
    Future<int> addLatte(WidgetTester tester) async {
      final latte = await addItem(
        tester,
        const MenuItem(name: 'Latte', category: 'Coffee', priceHint: 120),
      );
      await tester.runAsync(() async {
        final stock = await StockItemStore(db).add(milk);
        await RecipeStore(db).addLine(latte, stock, 177.441, inputUnit: 'oz');
      });
      return latte;
    }

    // goes to the archived list of the tab
    Future<void> openArchivedView(WidgetTester tester) async {
      await tester.tap(find.text('Archived'));
      await waitForDb(tester);
    }

    // taps a button and waits for the db
    Future<void> tapAndWait(WidgetTester tester, Finder button) async {
      await tester.tap(button);
      await waitForDb(tester);
    }

    testWidgets('adding has no archive button', (tester) async {
      await openAdd(tester);
      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('archive asks first, then hides the row', (tester) async {
      await addLatte(tester);
      await openMenu(tester);
      await tester.tap(find.text('Latte'));
      await waitForDb(tester);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Archive Latte?'), findsOneWidget);

      // cancel keeps it
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Edit menu item'), findsOneWidget);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      await tapAndWait(tester, find.widgetWithText(FilledButton, 'Archive'));

      expect(find.text('Archived Latte.'), findsOneWidget);
      expect(find.text('No menu items yet'), findsOneWidget);
    });

    testWidgets('archived view shows the item read only, restore brings it '
        'back with its recipe', (tester) async {
      final latte = await addLatte(tester);
      await tester.runAsync(() => store.archive(latte));
      await openMenu(tester);
      await openArchivedView(tester);

      expect(find.text('1 archived'), findsOneWidget);
      // archived items have no active lines, so no recipe column
      expect(find.text('Recipe'), findsNothing);
      expect(find.text('No recipe yet'), findsNothing);
      // only restored, never added
      expect(find.text('Add item'), findsNothing);

      await tester.tap(find.text('Latte'));
      await tester.pumpAndSettle();
      expect(find.text('Archived menu item'), findsOneWidget);
      expect(
        find.text('Restore it to edit it. Its recipe comes back too.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('menu_name_field')), findsNothing);

      await tapAndWait(tester, find.widgetWithText(FilledButton, 'Restore'));

      expect(find.text('Restored Latte.'), findsOneWidget);
      expect(find.text('No archived items'), findsOneWidget);

      await tester.tap(find.text('Active'));
      await waitForDb(tester);
      expect(find.text('1 stock item'), findsOneWidget);
      final line = (await tester.runAsync(
        () => RecipeStore(db).lines(latte),
      ))!.single;
      expect(line.amountText, '6 oz (177.44 ml)');
    });

    testWidgets('restore says which recipe lines were left out', (
      tester,
    ) async {
      final latte = await addLatte(tester);
      await tester.runAsync(() async {
        await store.archive(latte);
        final stock = StockItemStore(db);
        await stock.archive((await stock.findByName('Whole milk'))!.id!);
      });
      await openMenu(tester);
      await openArchivedView(tester);

      await tester.tap(find.text('Latte'));
      await tester.pumpAndSettle();
      await tapAndWait(tester, find.widgetWithText(FilledButton, 'Restore'));

      expect(
        find.text('Restored Latte. Left out archived stock items: Whole milk.'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => RecipeStore(db).lines(latte)),
        isEmpty,
      );
    });
  });

  testWidgets('a name of an archived item offers restore', (tester) async {
    final id = await addItem(
      tester,
      const MenuItem(name: 'Mocha', category: 'Coffee', priceHint: 120),
    );
    await tester.runAsync(() => store.archive(id));
    await openAdd(tester);

    await fill(tester, 'menu_name_field', 'mocha');
    await tapSave(tester);

    final restore = find.text('Restore it');
    await tester.ensureVisible(restore);
    await tester.pumpAndSettle();
    await tester.tap(restore);
    await tester.pumpAndSettle();

    expect(find.text('Restored Mocha.'), findsOneWidget);
    // back with its old price
    expect(find.text('120'), findsOneWidget);
  });
}
