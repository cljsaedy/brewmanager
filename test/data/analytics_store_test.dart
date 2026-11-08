import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/analytics_store.dart';
import 'package:brewmanager/data/count_line.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/count_math.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/owner/analytics/analytics_tab.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

// a 2000 ml bottle, low at 1 bottle
const StockItem syrup = StockItem(
  name: 'Caramel syrup',
  category: 'Syrups',
  baseUnit: BaseUnit.ml,
  countType: CountType.container,
  containerLabel: 'bottle',
  containerSize: 2000,
  lowMode: LowMode.containers,
  lowValue: 1,
);

// low at 5 packs
const StockItem friesPack = StockItem(
  name: 'Fries pack',
  category: 'Food',
  baseUnit: BaseUnit.pcs,
  countType: CountType.number,
  containerLabel: 'pack',
  lowMode: LowMode.exact,
  lowValue: 5,
);

// 3 scripted days, worked out by hand:
// nov 1 (opening count): fries 8, syrup 2 sealed + 50%
// nov 2: fries 8 -> 5 = used 3, 2 french fries ordered = expected 2, gap +1
//        syrup: 1 bottle finished, 10 lattes, 1 waffle (no recipe)
// nov 3: fries 5 -> 3 = used 2, 2 french fries ordered = expected 2, gap 0
//        1 waffle again
// so for fries: days counted 2 (the opening count has no usage), days with a gap 1, total gap +1
void main() {
  late Database db;

  CountRow rowOf(DraftDay day, int itemId) {
    return day.rows.firstWhere((row) => row.item.id == itemId);
  }

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    var now = DateTime.utc(2026, 11, 1, 10);
    final counts = CountStore(db, clock: () => now);
    final menu = MenuItemStore(db, clock: () => now);
    final recipes = RecipeStore(db, clock: () => now);

    final syrupId = await StockItemStore(db).add(syrup);
    final friesId = await StockItemStore(db).add(friesPack);
    final latteId = await menu.add(
      const MenuItem(name: 'Latte', category: 'Coffee'),
    );
    final friesMenuId = await menu.add(
      const MenuItem(name: 'French Fries', category: 'Food'),
    );
    final waffleId = await menu.add(
      const MenuItem(name: 'Waffle', category: 'Food'),
    );
    await recipes.addLine(latteId, syrupId, 30);
    await recipes.addLine(friesMenuId, friesId, 1);

    var day = await counts.loadDraft();
    await counts.saveNumberCount(rowOf(day, friesId).line.id, 8);
    await counts.saveContainerCount(
      rowOf(day, syrupId),
      sealed: 2,
      level: level50,
      exactQty: null,
    );
    await counts.submits.submit(day.day.id, date: '2026-11-01');

    now = DateTime.utc(2026, 11, 2, 10);
    day = await counts.loadDraft();
    await counts.saveNumberCount(rowOf(day, friesId).line.id, 5);
    await counts.finishContainer(rowOf(day, syrupId));
    for (var i = 0; i < 2; i++) {
      await counts.tally.add(day.day.id, friesMenuId);
    }
    for (var i = 0; i < 10; i++) {
      await counts.tally.add(day.day.id, latteId);
    }
    await counts.tally.add(day.day.id, waffleId);
    await counts.submits.submit(day.day.id, date: '2026-11-02');

    now = DateTime.utc(2026, 11, 3, 10);
    day = await counts.loadDraft();
    await counts.saveNumberCount(rowOf(day, friesId).line.id, 3);
    for (var i = 0; i < 2; i++) {
      await counts.tally.add(day.day.id, friesMenuId);
    }
    await counts.tally.add(day.day.id, waffleId);
    await counts.submits.submit(day.day.id, date: '2026-11-03');
  });

  tearDown(() async {
    await db.close();
  });

  group('the store', () {
    test('the newest submitted date', () async {
      expect(await AnalyticsStore(db).lastSubmittedDate(), '2026-11-03');
    });

    test('only number items, opening count left out', () async {
      final data = await AnalyticsStore(db).load('2026-11-01', '2026-11-03');

      expect([for (final item in data.numberItems) item.name], ['Fries pack']);
      final days = data.daysByItem.values.single;
      expect([for (final day in days) day.date], ['2026-11-02', '2026-11-03']);
      expect([for (final day in days) day.used], [3, 2]);
      expect([for (final day in days) day.expected], [2, 2]);
      expect([for (final day in days) day.gap], [1, 0]);
    });

    test('container checks and no recipe in the dates', () async {
      final data = await AnalyticsStore(db).load('2026-11-01', '2026-11-03');

      expect(data.checks.single.date, '2026-11-02');
      expect(data.checks.single.check.item.name, 'Caramel syrup');
      expect(data.noRecipe.single.name, 'Waffle');
      expect(data.noRecipe.single.days, 2);
    });

    test('dates outside the range are left out', () async {
      final data = await AnalyticsStore(db).load('2026-11-03', '2026-11-03');

      expect(data.daysByItem.values.single, hasLength(1));
      expect(data.checks, isEmpty);
      expect(data.noRecipe.single.days, 1);
    });
  });

  group('the tab', () {
    // the tab reads the db on its own, so give it real time
    Future<void> waitForDb(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openAnalytics(WidgetTester tester) async {
      useTabletScreen(tester);
      await tester.pumpWidget(
        BrewManagerApp(
          home: Scaffold(body: AnalyticsTab(store: AnalyticsStore(db))),
        ),
      );
      await waitForDb(tester);
    }

    // the left (0) or right (1) column scrolls, things further down are only built once scrolled to
    Future<void> scrollTo(WidgetTester tester, Finder finder, int column) {
      return tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).at(column),
      );
    }

    // the text of every cell in the gap table, row by row
    List<List<String>> tableText(WidgetTester tester) {
      final table = tester.widget<Table>(find.byKey(const Key('gap_table')));
      return [
        for (final row in table.children)
          [
            for (final cell in row.children)
              ((cell as Padding).child! as Text).data!,
          ],
      ];
    }

    testWidgets('shows the chart, the gap table and the side lists', (
      tester,
    ) async {
      await openAnalytics(tester);

      expect(find.byType(LineChart), findsOneWidget);
      await scrollTo(tester, find.byKey(const Key('gap_table')), 0);
      expect(tableText(tester), [
        ['Item', 'Days counted', 'Days with a gap', 'Total gap'],
        ['Fries pack', '2', '1', '+1 pack'],
      ]);
      expect(
        find.text(
          'Caramel syrup: 1 bottle (1,000 ml) finished. '
          'Based on orders since Nov 1, 300 ml should have been used.',
        ),
        findsOneWidget,
      );
      await scrollTo(tester, find.text('Waffle: ordered on 2 days'), 1);
      expect(find.text('Waffle: ordered on 2 days'), findsOneWidget);
      // owner wording
      expect(find.textContaining('Tally'), findsNothing);
      expect(find.textContaining('tally'), findsNothing);
    });

    testWidgets('by week puts the 2 days in 1 week', (tester) async {
      await openAnalytics(tester);
      LineChart chart() => tester.widget<LineChart>(find.byType(LineChart));
      expect(chart().data.lineBarsData.first.spots, hasLength(2));

      await tester.tap(find.text('By week'));
      await tester.pumpAndSettle();

      // nov 2 and nov 3 2026 are in the week of mon nov 2
      final spots = chart().data.lineBarsData.first.spots;
      expect(spots, hasLength(1));
      expect(spots.single.y, 5);
    });
  });
}
