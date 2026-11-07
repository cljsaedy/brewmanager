import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/layout/app_layout.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/main.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

// low at 5 pcs
const StockItem friesPack = StockItem(
  name: 'Fries pack',
  category: 'Food',
  baseUnit: BaseUnit.pcs,
  countType: CountType.number,
  lowMode: LowMode.exact,
  lowValue: 5,
);

void main() {
  late Database db;
  late CountStore store;
  // fake clock, nov 1 2026 is a sunday
  late DateTime now;
  late int friesId;
  late int friesMenuId;

  // the app reads the db on its own, so give it real time
  Future<void> waitForDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  // adds fries with a recipe and makes the draft dated nov 1
  Future<void> setUpDay() async {
    now = DateTime.utc(2026, 11, 1, 10);
    store = CountStore(db, clock: () => now);
    friesId = await StockItemStore(db).add(friesPack);
    final menu = MenuItemStore(db);
    friesMenuId = await menu.add(
      const MenuItem(name: 'French Fries', category: 'Food'),
    );
    await RecipeStore(db).addLine(friesMenuId, friesId, 1);
    await store.loadDraft();
  }

  Future<void> openApp(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(home: AppLayout(openCountStore: () async => store)),
    );
    await waitForDb(tester);
  }

  Future<void> openSubmit(WidgetTester tester) async {
    await tester.tap(find.text('Submit'));
    await waitForDb(tester);
  }

  Future<void> goToDateStep(WidgetTester tester) async {
    await openSubmit(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  // picks a day of nov in the date picker
  Future<void> pickDay(WidgetTester tester, String day) async {
    await tester.tap(find.text('Change date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(day));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<Map<String, Object?>> firstDay() async {
    final rows = await db.query('business_days', orderBy: 'id', limit: 1);
    return rows.first;
  }

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
  });

  tearDown(() async {
    await db.close();
  });

  group('review', () {
    testWidgets('warnings show but next still works', (tester) async {
      await tester.runAsync(() async {
        await setUpDay();
        final dayId = (await store.loadDraft()).day.id;
        final soup = await MenuItemStore(
          db,
        ).add(const MenuItem(name: 'Soup', category: 'Food'));
        await store.tally.add(dayId, soup);
        await store.tally.add(dayId, friesMenuId);
      });
      await openApp(tester);
      await openSubmit(tester);

      expect(find.text('Used today, not counted yet'), findsOneWidget);
      expect(find.text('Opening count, not counted yet'), findsOneWidget);
      expect(find.text('No recipe yet'), findsOneWidget);
      expect(find.text('Soup'), findsOneWidget);
      expect(find.text('Tally total: 2'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Submit count for Sun, Nov 1?'), findsOneWidget);
    });

    testWidgets('shows the events and notes', (tester) async {
      await tester.runAsync(() async {
        await setUpDay();
        var draft = await store.loadDraft();
        final row = draft.rows.single;
        await store.addRestock(row, 3);
        await store.saveNote(row.line.id, '2 packs expired');
        await store.saveDayNote(draft.day.id, 'power outage at 3pm');
      });
      await openApp(tester);
      await openSubmit(tester);

      expect(find.textContaining('Fries pack: +3 pcs ·'), findsOneWidget);
      expect(find.text('Fries pack: 2 packs expired'), findsOneWidget);
      expect(find.text('Day note: power outage at 3pm'), findsOneWidget);
    });

    testWidgets('back to count submits nothing', (tester) async {
      await tester.runAsync(setUpDay);
      await openApp(tester);
      await openSubmit(tester);

      await tester.tap(find.text('Back to count'));
      await waitForDb(tester);

      expect(find.text('Draft'), findsOneWidget);
      late Map<String, Object?> day;
      await tester.runAsync(() async => day = await firstDay());
      expect(day['status'], 'draft');
    });
  });

  group('date', () {
    testWidgets('on today change date is off', (tester) async {
      await tester.runAsync(setUpDay);
      await openApp(tester);
      await goToDateStep(tester);

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Change date'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.enabled, isFalse);
      expect(
        find.text('The date can only move forward, up to today.'),
        findsOneWidget,
      );
    });

    testWidgets('2 days behind the tablet warns', (tester) async {
      await tester.runAsync(setUpDay);
      now = DateTime.utc(2026, 11, 3, 10);
      await openApp(tester);
      await goToDateStep(tester);

      expect(
        find.text('This is 2 days ago. Did you skip a day?'),
        findsOneWidget,
      );
    });

    testWidgets('open on the skipped days covers them', (tester) async {
      await tester.runAsync(setUpDay);
      now = DateTime.utc(2026, 11, 3, 10);
      await openApp(tester);
      await goToDateStep(tester);

      await pickDay(tester, '3');
      expect(find.text('Was the cafe open on those days?'), findsOneWidget);
      await tester.tap(find.text('Yes, open'));
      await tester.pumpAndSettle();

      expect(find.text('Submit count for Tue, Nov 3?'), findsOneWidget);
      expect(find.text('Covers Nov 1–3'), findsOneWidget);
      expect(find.textContaining('days ago'), findsNothing);

      await tester.tap(find.text('Submit'));
      await waitForDb(tester);

      late Map<String, Object?> day;
      await tester.runAsync(() async => day = await firstDay());
      expect(day['business_date'], '2026-11-03');
      expect(day['covers_from'], '2026-11-01');
    });

    testWidgets('closed on the skipped days saves them closed', (tester) async {
      await tester.runAsync(setUpDay);
      now = DateTime.utc(2026, 11, 3, 10);
      await openApp(tester);
      await goToDateStep(tester);

      await pickDay(tester, '3');
      await tester.tap(find.text('No, closed'));
      await tester.pumpAndSettle();

      expect(find.text('Closed: Nov 1, Nov 2'), findsOneWidget);

      await tester.tap(find.text('Submit'));
      await waitForDb(tester);

      late List<Map<String, Object?>> closed;
      await tester.runAsync(() async {
        closed = await db.query('business_days', where: "status = 'closed'");
      });
      expect(closed, hasLength(2));
    });

    testWidgets('cancelling the question keeps the date', (tester) async {
      await tester.runAsync(setUpDay);
      now = DateTime.utc(2026, 11, 3, 10);
      await openApp(tester);
      await goToDateStep(tester);

      await pickDay(tester, '3');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Submit count for Sun, Nov 1?'), findsOneWidget);
    });
  });

  group('submitted', () {
    testWidgets('lists restock items, then opens the next draft', (
      tester,
    ) async {
      await tester.runAsync(setUpDay);
      await openApp(tester);
      await goToDateStep(tester);

      await tester.tap(find.text('Submit'));
      await waitForDb(tester);

      expect(find.text('Submitted Sun, Nov 1'), findsOneWidget);
      // the fries are at 0, at or below their level of 5
      expect(find.text('Restock recommended'), findsOneWidget);
      expect(find.text('Fries pack'), findsOneWidget);

      await tester.tap(find.text("Open next day's draft"));
      await waitForDb(tester);

      expect(find.text('Mon, Nov 2'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets('a double tap on submit only submits once', (tester) async {
      await tester.runAsync(setUpDay);
      await openApp(tester);
      await goToDateStep(tester);

      final submit = find.text('Submit');
      await tester.tap(submit);
      await tester.tap(submit, warnIfMissed: false);
      await waitForDb(tester);

      expect(find.text('Submitted Sun, Nov 1'), findsOneWidget);
      late List<Map<String, Object?>> days;
      await tester.runAsync(() async => days = await db.query('business_days'));
      expect(days, hasLength(1));
    });

    testWidgets('no expected number shows on any step', (tester) async {
      await tester.runAsync(() async {
        await setUpDay();
        final draft = await store.loadDraft();
        // a first day of 8, so the next day compares
        await store.saveNumberCount(draft.rows.single.line.id, 8);
        await store.submits.submit(draft.day.id, date: '2026-11-01');

        final next = await store.loadDraft();
        await store.saveNumberCount(next.rows.single.line.id, 6);
        for (var i = 0; i < 7; i++) {
          await store.tally.add(next.day.id, friesMenuId);
        }
      });
      await openApp(tester);

      void expectNoExpected() {
        expect(find.textContaining('xpected'), findsNothing);
        expect(find.textContaining('gap'), findsNothing);
        // 2 used - 7 expected = a gap of -5, it must not show
        expect(find.textContaining('-5'), findsNothing);
      }

      await openSubmit(tester);
      expect(find.text('Tally total: 7'), findsOneWidget);
      expectNoExpected();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expectNoExpected();

      await tester.tap(find.text('Submit'));
      await waitForDb(tester);
      expect(find.textContaining('Submitted'), findsOneWidget);
      expectNoExpected();
    });
  });

  testWidgets('a long review fits the tablet screen', (tester) async {
    await tester.runAsync(() async {
      await setUpDay();
      final draft = await store.loadDraft();
      final row = draft.rows.single;
      for (var i = 0; i < 30; i++) {
        await store.addRestock(row, 1);
      }
      await store.saveNote(row.line.id, 'A long note. ' * 40);
    });
    await openApp(tester);
    await openSubmit(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Next'), findsOneWidget);
  });
}
