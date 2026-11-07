import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/count/count_badges.dart';
import 'package:brewmanager/count/count_tab.dart';
import 'package:brewmanager/data/count_line.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/logic/count_math.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/theme/app_theme.dart';
import 'package:brewmanager/widgets/status_chip.dart';

import '../helpers/tablet_screen.dart';

const StockItem syrup = StockItem(
  id: 1,
  name: 'Caramel syrup',
  category: 'Syrups',
  baseUnit: BaseUnit.ml,
  countType: CountType.container,
  containerLabel: 'bottle',
  containerSize: 2000,
  lowMode: LowMode.containers,
  lowValue: 1,
);

const StockItem friesPack = StockItem(
  id: 2,
  name: 'Fries pack',
  category: 'Food',
  baseUnit: BaseUnit.pcs,
  countType: CountType.number,
  lowMode: LowMode.exact,
  lowValue: 5,
);

// a count line with only the values the test cares about
CountLine line({
  double start = 0,
  double inQty = 0,
  int out = 0,
  double end = 0,
  bool isOpening = false,
}) {
  return CountLine(
    id: 1,
    dayId: 1,
    stockItemId: 1,
    startQty: start,
    startIsExact: true,
    inQty: inQty,
    outCount: out,
    sealed: 0,
    level: levelNone,
    exactQty: null,
    endQty: end,
    endIsExact: true,
    touched: false,
    isOpening: isOpening,
    note: null,
  );
}

DraftDay draftOf(List<CountRow> rows) {
  return DraftDay(
    day: const BusinessDay(id: 1, businessDate: '2026-11-01', status: 'draft'),
    rows: rows,
  );
}

Future<void> showTab(WidgetTester tester, DraftDay? draft) async {
  useTabletScreen(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: CountTab(draft: draft, store: null, onChanged: () {}),
      ),
    ),
  );
}

// the badge only, the filter button has the same words
final Finder restockChip = find.widgetWithText(StatusChip, restockBadge);

void main() {
  testWidgets('with the keyboard open the title and filters hide', (
    tester,
  ) async {
    // bigger than a real keyboard since this test has no top bar taking height
    tester.view.viewInsets = const FakeViewPadding(bottom: 500);
    addTearDown(tester.view.resetViewInsets);

    await showTab(
      tester,
      draftOf([CountRow(line: line(end: 6), item: friesPack)]),
    );

    expect(find.text('Logbook'), findsNothing);
    expect(find.byKey(const Key('filter_all')), findsNothing);
    expect(find.text('End'), findsOneWidget);
    expect(find.text('Fries pack'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('restock recommended', () {
    Future<void> tapFilter(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    // syrup is low at 1 bottle = 2000 ml, fries at 5 pcs
    final DraftDay mixed = draftOf([
      CountRow(line: line(end: 6), item: friesPack),
      CountRow(line: line(end: 1000), item: syrup),
    ]);

    testWidgets('the badge shows at the level, not above it', (tester) async {
      await showTab(
        tester,
        draftOf([
          CountRow(line: line(end: 2000), item: syrup),
          CountRow(line: line(end: 6), item: friesPack),
        ]),
      );
      expect(restockChip, findsOneWidget);
    });

    testWidgets('a line can show both badges', (tester) async {
      await showTab(
        tester,
        draftOf([CountRow(line: line(isOpening: true), item: friesPack)]),
      );

      expect(find.text(openingCountBadge), findsOneWidget);
      expect(restockChip, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the filter only shows low items', (tester) async {
      await showTab(tester, mixed);
      expect(find.text('Fries pack'), findsOneWidget);

      await tapFilter(tester, 'filter_restock');

      expect(find.text('Fries pack'), findsNothing);
      expect(find.text('FOOD'), findsNothing);
      expect(find.text('Caramel syrup'), findsOneWidget);
      expect(find.text('SYRUPS'), findsOneWidget);
      // the header still counts all the items
      expect(find.text('2 items'), findsOneWidget);
    });

    testWidgets('All brings every row back', (tester) async {
      await showTab(tester, mixed);
      await tapFilter(tester, 'filter_restock');

      await tapFilter(tester, 'filter_all');

      expect(find.text('Fries pack'), findsOneWidget);
    });

    testWidgets('nothing low says so', (tester) async {
      await showTab(
        tester,
        draftOf([CountRow(line: line(end: 6), item: friesPack)]),
      );

      await tapFilter(tester, 'filter_restock');

      expect(find.text('No items need restocking'), findsOneWidget);
    });
  });

  group('search', () {
    final DraftDay mixed = draftOf([
      CountRow(line: line(end: 6), item: friesPack),
      CountRow(line: line(end: 1000), item: syrup),
      CountRow(
        line: line(end: 5000),
        item: syrup.copyWith(name: 'Vanilla syrup'),
      ),
    ]);

    Future<void> search(WidgetTester tester, String words) async {
      await tester.enterText(find.byKey(const Key('count_search')), words);
      await tester.pumpAndSettle();
    }

    testWidgets('finds any part of the name, ignoring case', (tester) async {
      await showTab(tester, mixed);

      await search(tester, '  SYRUP ');

      expect(find.text('Caramel syrup'), findsOneWidget);
      expect(find.text('Vanilla syrup'), findsOneWidget);
      expect(find.text('Fries pack'), findsNothing);
      // the title goes too since no row is left under it
      expect(find.text('FOOD'), findsNothing);
      expect(find.text('3 items'), findsOneWidget);
    });

    testWidgets('works together with the restock filter', (tester) async {
      await showTab(tester, mixed);
      await tester.tap(find.byKey(const Key('filter_restock')));
      await tester.pumpAndSettle();

      await search(tester, 'syrup');

      // vanilla has 2.5 bottles, above its level of 1
      expect(find.text('Caramel syrup'), findsOneWidget);
      expect(find.text('Vanilla syrup'), findsNothing);
    });

    testWidgets('no match says so', (tester) async {
      await showTab(tester, mixed);

      await search(tester, 'matcha');

      expect(find.text('No items match "matcha"'), findsOneWidget);
    });

    testWidgets('the x clears the search', (tester) async {
      await showTab(tester, mixed);
      await search(tester, 'matcha');

      await tester.tap(find.byKey(const Key('count_search_clear')));
      await tester.pumpAndSettle();

      expect(find.text('Fries pack'), findsOneWidget);
      expect(find.byKey(const Key('count_search_clear')), findsNothing);
    });

    testWidgets('typing stays when the keyboard opens', (tester) async {
      await showTab(tester, mixed);
      await tester.tap(find.byKey(const Key('count_search')));
      await search(tester, 'syrup');

      tester.view.viewInsets = const FakeViewPadding(bottom: 500);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(find.text('Logbook'), findsNothing);
      final box = tester.widget<TextField>(
        find.byKey(const Key('count_search')),
      );
      expect(box.focusNode!.hasFocus, isTrue);
      expect(box.controller!.text, 'syrup');
      expect(find.text('Fries pack'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('shows a loading circle until the draft is ready', (
    tester,
  ) async {
    await showTab(tester, null);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('no stock items shows a message', (tester) async {
    await showTab(tester, draftOf([]));
    expect(find.text('No stock items yet'), findsOneWidget);
  });

  testWidgets('the columns use the rule 3 labels', (tester) async {
    await showTab(tester, draftOf([]));
    for (final label in ['Name', 'Unit', 'Start', 'In', 'Out', 'End']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('container items show in containers', (tester) async {
    await showTab(
      tester,
      draftOf([
        CountRow(
          line: line(start: 5500, inQty: 4000, out: 1, end: 7000),
          item: syrup,
        ),
      ]),
    );

    expect(find.text('Caramel syrup'), findsOneWidget);
    expect(find.text('bottle'), findsOneWidget);
    expect(find.text('2.75'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3.5'), findsOneWidget);
  });

  testWidgets('a container with no name typed says container', (tester) async {
    final item = StockItem(
      id: 1,
      name: 'Beans',
      category: 'Coffee',
      baseUnit: BaseUnit.g,
      countType: CountType.container,
      containerSize: 250,
      lowMode: LowMode.containers,
      lowValue: 1,
    );
    await showTab(tester, draftOf([CountRow(line: line(), item: item)]));

    expect(find.text('container'), findsOneWidget);
  });

  testWidgets('number items show pieces used in Out', (tester) async {
    await showTab(
      tester,
      draftOf([
        CountRow(line: line(start: 12, inQty: 5, end: 9), item: friesPack),
      ]),
    );

    expect(find.text('pcs'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    // 12 + 5 - 9 = 8
    expect(find.text('8'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('a number item on its opening count shows no usage', (
    tester,
  ) async {
    await showTab(
      tester,
      draftOf([
        CountRow(line: line(end: 20, isOpening: true), item: friesPack),
      ]),
    );

    // start 0 - end 20 would say -20
    expect(find.text('—'), findsOneWidget);
    expect(find.text('-20'), findsNothing);
  });

  testWidgets('container Out stays containers finished', (tester) async {
    await showTab(
      tester,
      draftOf([
        CountRow(line: line(start: 6000, out: 1, end: 2000), item: syrup),
      ]),
    );

    // 3 bottles at the start, 1 at the end, but only 1 was finished
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('each category gets one title, ignoring case', (tester) async {
    await showTab(
      tester,
      draftOf([
        CountRow(line: line(), item: friesPack),
        CountRow(line: line(), item: syrup),
        CountRow(
          line: line(),
          item: syrup.copyWith(name: 'Vanilla syrup', category: 'syrups'),
        ),
      ]),
    );

    expect(find.text('FOOD'), findsOneWidget);
    expect(find.text('SYRUPS'), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget);
  });

  testWidgets('the opening count badge only shows on an opening line', (
    tester,
  ) async {
    await showTab(
      tester,
      draftOf([
        CountRow(line: line(isOpening: true), item: friesPack),
        CountRow(line: line(), item: syrup),
      ]),
    );

    expect(find.text(openingCountBadge), findsOneWidget);
    expect(openingCountBadge, 'Opening count: please count');
  });
}
