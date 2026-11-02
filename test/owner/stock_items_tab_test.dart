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
}
