import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/security/key_store.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/layout/app_layout.dart';
import 'package:brewmanager/logic/count_math.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/main.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

// a 2000 ml bottle item
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

void main() {
  late Database db;
  late CountStore store;
  // fake clock, nov 1 2026 is a sunday
  late DateTime now;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    now = DateTime.utc(2026, 11, 1, 10);
    // empty fake keys, so submit never touches secure storage or the internet
    store = CountStore(db, clock: () => now, keys: MemoryKeyStore());
  });

  tearDown(() async {
    await db.close();
  });

  // the app reads the db on its own, so give it real time
  Future<void> waitForDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  // opens the app on the history tab
  Future<void> openHistory(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(home: AppLayout(openCountStore: () async => store)),
    );
    await waitForDb(tester);
    await tester.tap(find.text('History'));
    await waitForDb(tester);
  }

  // nov 1: syrup counted at 2 sealed + 50%, a note, 3 lattes and a day note
  // nov 2 and 3: closed, nov 4: submitted with nothing changed
  Future<void> addDays() async {
    final syrupId = await StockItemStore(db).add(syrup);
    final latte = await MenuItemStore(
      db,
    ).add(const MenuItem(name: 'Latte', category: 'Coffee'));
    await RecipeStore(db).addLine(latte, syrupId, 30);

    final draft = await store.loadDraft();
    final row = draft.rows.single;
    await store.saveContainerCount(
      row,
      sealed: 2,
      level: level50,
      exactQty: null,
    );
    await store.saveNote(row.line.id, 'cap was loose');
    await store.saveDayNote(draft.day.id, 'power outage at 3pm');
    for (var i = 0; i < 3; i++) {
      await store.tally.add(draft.day.id, latte);
    }
    await store.submits.submit(draft.day.id, date: '2026-11-01');

    final next = await store.loadDraft();
    await store.submits.submit(
      next.day.id,
      date: '2026-11-04',
      skippedDaysOpen: false,
    );
  }

  testWidgets('no days yet says so', (tester) async {
    await openHistory(tester);

    expect(find.text('No submitted days yet'), findsOneWidget);
  });

  testWidgets('lists the days newest first and opens the newest', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openHistory(tester);

    final dates = ['Wed, Nov 4', 'Tue, Nov 3', 'Mon, Nov 2', 'Sun, Nov 1'];
    final tops = [
      for (final date in dates) tester.getTopLeft(find.text(date).first).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text('Closed'), findsNWidgets(2));
    // the newest is open, its date is in the list and the header
    expect(find.text('Wed, Nov 4'), findsNWidgets(2));
  });

  testWidgets('a submitted day shows its count, tally and notes', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openHistory(tester);

    await tester.tap(find.text('Sun, Nov 1').first);
    await waitForDb(tester);

    expect(find.text('Caramel syrup'), findsOneWidget);
    expect(find.text('bottle • ml'), findsOneWidget);
    // 2 sealed + 50% = 2.5 bottles
    expect(find.text('2.5'), findsOneWidget);
    expect(find.text('Note: cap was loose'), findsOneWidget);
    expect(find.text('Latte'), findsOneWidget);
    expect(find.text('× 3'), findsOneWidget);
    // the header says when it was submitted, on the tablet's clock
    expect(find.textContaining('Submitted '), findsOneWidget);

    // the day note is at the bottom, a list only builds what is on screen
    await tester.scrollUntilVisible(
      find.text('power outage at 3pm'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('power outage at 3pm'), findsOneWidget);
  });

  testWidgets('a closed day says so', (tester) async {
    await tester.runAsync(addDays);
    await openHistory(tester);

    await tester.tap(find.text('Tue, Nov 3').first);
    await waitForDb(tester);

    expect(find.text('The cafe was closed this day.'), findsOneWidget);
  });

  testWidgets('no expected number shows', (tester) async {
    await tester.runAsync(addDays);
    await openHistory(tester);
    await tester.tap(find.text('Sun, Nov 1').first);
    await waitForDb(tester);

    expect(find.textContaining('xpected'), findsNothing);
    expect(find.textContaining('gap'), findsNothing);
    // 3 lattes x 30 ml = 90 ml expected
    expect(find.textContaining('90'), findsNothing);
  });

  testWidgets('a new submit shows up in history', (tester) async {
    await openHistory(tester);
    expect(find.text('No submitted days yet'), findsOneWidget);

    await tester.tap(find.text('Submit'));
    await waitForDb(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await waitForDb(tester);
    await tester.tap(find.text("Open next day's draft"));
    await waitForDb(tester);

    expect(find.text('Sun, Nov 1'), findsNWidgets(2));
    expect(find.text('Mon, Nov 2'), findsOneWidget);
  });
}
