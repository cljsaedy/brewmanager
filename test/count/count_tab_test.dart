import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/count/count_tab.dart';
import 'package:brewmanager/data/count_line.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/logic/count_math.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/theme/app_theme.dart';

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
      home: Scaffold(body: CountTab(draft: draft)),
    ),
  );
}

void main() {
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

  testWidgets('number items show in pcs with no Out', (tester) async {
    await showTab(
      tester,
      draftOf([CountRow(line: line(start: 12, end: 9), item: friesPack)]),
    );

    expect(find.text('pcs'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
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
