import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/count/count_badges.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/data/tally_store.dart';
import 'package:brewmanager/layout/app_layout.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/tally/tally_tab.dart';
import 'package:brewmanager/theme/app_theme.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late int dayId;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    dayId = (await CountStore(db).loadDraft()).day.id;
  });

  tearDown(() async {
    await db.close();
  });

  // the db work runs for real, the test clock has to step aside for it
  Future<void> waitForDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<int> addItem(
    WidgetTester tester,
    String name, {
    String category = 'Coffee',
    double? price,
  }) async {
    final id = await tester.runAsync(
      () => MenuItemStore(
        db,
      ).add(MenuItem(name: name, category: category, priceHint: price)),
    );
    return id!;
  }

  Future<void> showTab(WidgetTester tester, {VoidCallback? onChanged}) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TallyTab(
            dayId: dayId,
            store: TallyStore(db),
            onChanged: onChanged ?? () {},
          ),
        ),
      ),
    );
    await waitForDb(tester);
  }

  Future<List<Map<String, Object?>>> savedLines(WidgetTester tester) async {
    final rows = await tester.runAsync(() => db.query('tally_lines'));
    return rows!;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await waitForDb(tester);
  }

  testWidgets('shows a loading circle until the day is known', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TallyTab(dayId: null, store: null, onChanged: () {}),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Nothing tallied yet'), findsOneWidget);
  });

  testWidgets('no menu items shows a message', (tester) async {
    await showTab(tester);
    expect(find.text('No menu items yet'), findsOneWidget);
  });

  testWidgets('groups items by category with the price as a hint', (
    tester,
  ) async {
    await addItem(tester, 'Latte', price: 120);
    await addItem(tester, 'Fries', category: 'Food');

    await showTab(tester);

    expect(find.text('COFFEE'), findsOneWidget);
    expect(find.text('FOOD'), findsOneWidget);
    expect(find.text('Latte'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a tile adds 1 and saves it', (tester) async {
    final id = await addItem(tester, 'Latte');
    await showTab(tester);

    await tapKey(tester, 'tally_tile_$id');
    await tapKey(tester, 'tally_tile_$id');

    expect(find.text('Latte × 2'), findsOneWidget);
    expect(find.byKey(Key('tally_count_$id')), findsOneWidget);
    final lines = await savedLines(tester);
    expect(lines.single['qty'], 2);
  });

  testWidgets('fast taps all count', (tester) async {
    final id = await addItem(tester, 'Latte');
    await showTab(tester);

    // no waiting between the taps
    await tester.tap(find.byKey(Key('tally_tile_$id')));
    await tester.pump();
    await tester.tap(find.byKey(Key('tally_tile_$id')));
    await tester.pump();
    await tester.tap(find.byKey(Key('tally_tile_$id')));
    await waitForDb(tester);

    expect(find.text('Latte × 3'), findsOneWidget);
    expect((await savedLines(tester)).single['qty'], 3);
  });

  testWidgets('- and + in the list fix the number', (tester) async {
    final id = await addItem(tester, 'Latte');
    await showTab(tester);
    await tapKey(tester, 'tally_tile_$id');

    await tapKey(tester, 'tally_plus_$id');
    expect(find.text('Latte × 2'), findsOneWidget);

    await tapKey(tester, 'tally_minus_$id');
    expect(find.text('Latte × 1'), findsOneWidget);
    expect((await savedLines(tester)).single['qty'], 1);
  });

  testWidgets('going down to 0 clears the line', (tester) async {
    final id = await addItem(tester, 'Latte');
    await showTab(tester);
    await tapKey(tester, 'tally_tile_$id');

    await tapKey(tester, 'tally_minus_$id');

    expect(find.text('Nothing tallied yet'), findsOneWidget);
    expect(find.byKey(Key('tally_count_$id')), findsNothing);
    expect(await savedLines(tester), isEmpty);
  });

  testWidgets('the tally is still there after opening the tab again', (
    tester,
  ) async {
    final id = await addItem(tester, 'Latte');
    await showTab(tester);
    await tapKey(tester, 'tally_tile_$id');

    await tester.pumpWidget(const SizedBox());
    await showTab(tester);

    expect(find.text('Latte × 1'), findsOneWidget);
  });

  testWidgets('an archived item stays in the list but leaves the grid', (
    tester,
  ) async {
    final id = await addItem(tester, 'Latte');
    await addItem(tester, 'Mocha');
    await tester.runAsync(() => TallyStore(db).add(dayId, id));
    await tester.runAsync(() => MenuItemStore(db).archive(id));

    await showTab(tester);

    expect(find.text('Latte × 1'), findsOneWidget);
    expect(find.byKey(Key('tally_tile_$id')), findsNothing);
    expect(find.text('Mocha'), findsOneWidget);
  });

  testWidgets('long names fit on the tablet', (tester) async {
    for (var i = 0; i < 12; i++) {
      final id = await addItem(tester, 'Iced Caramel Macchiato (Regular) $i');
      await tester.runAsync(() => TallyStore(db).add(dayId, id));
    }

    await showTab(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('every save tells the app layout', (tester) async {
    final id = await addItem(tester, 'Latte');
    var calls = 0;
    await showTab(tester, onChanged: () => calls++);

    await tapKey(tester, 'tally_tile_$id');
    await tapKey(tester, 'tally_minus_$id');

    expect(calls, 2);
  });

  group('used today on the count tab', () {
    final badge = find.text(doubleCheckBadge);

    // a syrup in a latte's recipe, and the app open with the latte tile ready
    Future<int> openApp(WidgetTester tester) async {
      final stockId = await tester.runAsync(
        () => StockItemStore(db).add(
          const StockItem(
            name: 'Caramel syrup',
            category: 'Syrups',
            baseUnit: BaseUnit.ml,
            countType: CountType.container,
            containerLabel: 'bottle',
            containerSize: 2000,
            lowMode: LowMode.containers,
            lowValue: 0,
          ),
        ),
      );
      final menuId = await addItem(tester, 'Latte');
      await tester.runAsync(
        () => RecipeStore(db).addLine(menuId, stockId!, 30),
      );

      useTabletScreen(tester);
      await tester.pumpWidget(
        BrewManagerApp(
          home: AppLayout(openCountStore: () async => CountStore(db)),
        ),
      );
      await waitForDb(tester);
      return menuId;
    }

    Future<void> openTab(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('a tally shows the badge without leaving the app', (
      tester,
    ) async {
      final menuId = await openApp(tester);
      expect(badge, findsNothing);

      await openTab(tester, 'Tally');
      await tapKey(tester, 'tally_tile_$menuId');
      await openTab(tester, 'Count');

      expect(badge, findsOneWidget);
    });

    testWidgets('taking the tally back to 0 removes the badge', (tester) async {
      final menuId = await openApp(tester);
      await openTab(tester, 'Tally');
      await tapKey(tester, 'tally_tile_$menuId');

      await tapKey(tester, 'tally_minus_$menuId');
      await openTab(tester, 'Count');

      expect(badge, findsNothing);
    });

    testWidgets('counting the item removes the badge, the filter keeps it', (
      tester,
    ) async {
      final menuId = await openApp(tester);
      await openTab(tester, 'Tally');
      await tapKey(tester, 'tally_tile_$menuId');
      await openTab(tester, 'Count');

      await tester.tap(find.text('Caramel syrup'));
      await tester.pumpAndSettle();
      expect(badge, findsOneWidget);
      await tester.tap(find.byKey(const Key('sealed_plus')));
      await waitForDb(tester);

      expect(badge, findsNothing);
      await tester.tap(find.byKey(const Key('filter_used')));
      await tester.pumpAndSettle();
      expect(find.text('No items used today'), findsNothing);
    });

    testWidgets('no expected numbers reach the barista side', (tester) async {
      final menuId = await openApp(tester);
      await openTab(tester, 'Tally');
      await tapKey(tester, 'tally_tile_$menuId');
      await openTab(tester, 'Count');

      // 30 is the recipe amount
      expect(find.textContaining('30'), findsNothing);
    });
  });

  testWidgets('the app layout opens the tally of the draft day', (
    tester,
  ) async {
    final id = await addItem(tester, 'Latte');
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(
        home: AppLayout(openCountStore: () async => CountStore(db)),
      ),
    );
    await waitForDb(tester);

    await tester.tap(find.text('Tally'));
    await tester.pumpAndSettle();
    await tapKey(tester, 'tally_tile_$id');

    expect(find.text('Latte × 1'), findsOneWidget);
    expect((await savedLines(tester)).single['day_id'], dayId);
  });

  // like a restore: when the owner section closes, the app layout gets a store on another db
  // the tabs must start again with that new store, not stay on the old one
  testWidgets('after the owner section, the tally shows the new db (restore)', (
    tester,
  ) async {
    await addItem(tester, 'Latte');
    // the "restored" db: same menu item, and 3 lattes already tallied on its draft
    final restored = await openTestDatabase(noIsolate: true);
    addTearDown(restored.close);
    await tester.runAsync(() async {
      final latte = await MenuItemStore(
        restored,
      ).add(const MenuItem(name: 'Latte', category: 'Coffee'));
      final day = await CountStore(restored).loadDraft();
      for (var i = 0; i < 3; i++) {
        await TallyStore(restored).add(day.day.id, latte);
      }
    });
    // flips at the moment of the restore, the app can ask for its store several times before that
    var restoredNow = false;
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(
        home: AppLayout(
          openCountStore: () async => CountStore(restoredNow ? restored : db),
        ),
      ),
    );
    await waitForDb(tester);
    await tester.tap(find.text('Tally'));
    await tester.pumpAndSettle();
    expect(find.text('Latte × 3'), findsNothing);

    // a screen opens on top and closes again, like the owner section after a restore
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Owner')),
      ),
    );
    await tester.pumpAndSettle();
    // a restore closes the old db before the owner section closes
    await tester.runAsync(db.close);
    restoredNow = true;
    navigator.pop();
    await waitForDb(tester);
    await waitForDb(tester);

    expect(find.text('Latte × 3'), findsOneWidget);
  });
}
