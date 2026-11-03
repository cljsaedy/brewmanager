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
    expect(find.text("Doesn't use stock"), findsOneWidget);
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

    expect(find.text('Add menu item'), findsNothing);
    expect(find.text('Saved Iced Americano (Large).'), findsOneWidget);
    expect(find.text('Iced Americano (Large)'), findsOneWidget);

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
    await tester.tap(find.byKey(const Key('no_stock_box')));
    await tester.pump();
    await tapSave(tester);

    expect(find.text("Doesn't use stock"), findsOneWidget);
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
