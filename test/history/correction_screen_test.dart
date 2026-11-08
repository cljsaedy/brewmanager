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
  late DateTime now;
  late int syrupId;
  late int friesId;
  late int friesMenuId;
  late int day1;
  late int day2;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    now = DateTime.utc(2026, 11, 1, 10);
    store = CountStore(db, clock: () => now);
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

  // nov 1: 8 fries, syrup at 2 sealed + 50%
  // nov 2: 5 fries, 2 french fries tallied, syrup untouched
  Future<void> addDays() async {
    syrupId = await StockItemStore(db).add(syrup);
    friesId = await StockItemStore(db).add(friesPack);
    friesMenuId = await MenuItemStore(
      db,
    ).add(const MenuItem(name: 'French Fries', category: 'Food'));
    await RecipeStore(db).addLine(friesMenuId, friesId, 1);

    var draft = await store.loadDraft();
    for (final row in draft.rows) {
      if (row.item.id == friesId) {
        await store.saveNumberCount(row.line.id, 8);
      } else {
        await store.saveContainerCount(
          row,
          sealed: 2,
          level: level50,
          exactQty: null,
        );
      }
    }
    day1 = draft.day.id;
    await store.submits.submit(day1, date: '2026-11-01');

    draft = await store.loadDraft();
    final fries = draft.rows.firstWhere((row) => row.item.id == friesId);
    await store.saveNumberCount(fries.line.id, 5);
    await store.tally.add(draft.day.id, friesMenuId);
    await store.tally.add(draft.day.id, friesMenuId);
    day2 = draft.day.id;
    await store.submits.submit(day2, date: '2026-11-02');
    now = DateTime.utc(2026, 11, 3, 10);
  }

  Future<void> openHistory(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(home: AppLayout(openCountStore: () async => store)),
    );
    await waitForDb(tester);
    await tester.tap(find.text('History'));
    await waitForDb(tester);
  }

  Future<void> openCorrect(WidgetTester tester) async {
    await openHistory(tester);
    await tester.tap(find.byKey(const Key('correct_button')));
    await waitForDb(tester);
  }

  // the form can be taller than the screen, a list only builds what is on screen
  Future<void> scrollToReason(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('reason_field')),
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('correction_form')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }

  // types the reason and presses add change, nothing is saved yet
  Future<void> typeReasonAndAdd(WidgetTester tester, String reason) async {
    await scrollToReason(tester);
    await tester.enterText(find.byKey(const Key('reason_field')), reason);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('add_change')));
    await tester.tap(find.byKey(const Key('add_change')));
    await tester.pumpAndSettle();
  }

  Future<void> saveAll(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('save_corrections')));
    await waitForDb(tester);
  }

  bool enabled(WidgetTester tester, String key) {
    return tester.widget<ButtonStyleButton>(find.byKey(Key(key))).enabled;
  }

  Future<List<Map<String, Object?>>> rows(
    WidgetTester tester,
    String table,
  ) async {
    late List<Map<String, Object?>> result;
    await tester.runAsync(() async => result = await db.query(table));
    return result;
  }

  testWidgets('correct shows only on the newest submitted day', (tester) async {
    await tester.runAsync(addDays);
    await openHistory(tester);

    expect(find.byKey(const Key('correct_button')), findsOneWidget);

    await tester.tap(find.text('Sun, Nov 1').first);
    await waitForDb(tester);

    expect(find.byKey(const Key('correct_button')), findsNothing);
  });

  testWidgets('the pick hint shows before anything is picked', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    expect(
      find.text('Pick an item, a tally line or the day note on the left.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.touch_app_outlined), findsOneWidget);
    expect(enabled(tester, 'save_corrections'), isFalse);
  });

  testWidgets('add change saves nothing, save corrections saves it', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await tester.pump();
    // no reason yet
    expect(enabled(tester, 'add_change'), isFalse);

    await typeReasonAndAdd(tester, 'typo');

    // waiting: the list shows the new values, the db still has the old ones
    expect(find.text('Changed'), findsNWidgets(2));
    expect(find.text('End 6 · In 0 · Out 2'), findsOneWidget);
    expect(find.text('Save corrections (1)'), findsOneWidget);
    expect(await rows(tester, 'corrections'), isEmpty);
    expect(await rows(tester, 'outbox'), isEmpty);

    await saveAll(tester);

    expect(
      find.text('1 correction saved. The owner will get an email about it.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Fries pack End 5 → 6 pcs'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Fries pack End 5 → 6 pcs'), findsOneWidget);
    expect(find.textContaining('Reason: typo · '), findsOneWidget);
  });

  testWidgets('a container fix with sealed + and a level', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$syrupId')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('sealed_value'))).data,
      '2',
    );
    await tester.tap(find.byKey(const Key('sealed_plus')));
    await tester.tap(find.text('75%'));
    await tester.pump();
    await typeReasonAndAdd(tester, 'missed one');
    await saveAll(tester);

    late List<Map<String, Object?>> lines;
    await tester.runAsync(() async {
      lines = await db.query(
        'count_lines',
        where: 'day_id = ? AND stock_item_id = ?',
        whereArgs: [day2, syrupId],
      );
    });
    expect(lines.single['sealed'], 3);
    expect(lines.single['level'], level75);
    // 3 x 2000 + 75% of 2000
    expect(lines.single['end_qty'], 7500);
  });

  testWidgets('a tally fix and a day note fix go in 1 email', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_tally_$friesMenuId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty_plus')));
    await tester.pump();
    await typeReasonAndAdd(tester, 'missed a receipt');
    expect(find.text('× 3'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('fix_dayNote_0')));
    await tester.tap(find.byKey(const Key('fix_dayNote_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('day_note_field')),
      'power outage',
    );
    await typeReasonAndAdd(tester, 'forgot');
    expect(find.text('Save corrections (2)'), findsOneWidget);

    await saveAll(tester);

    expect(
      find.text('2 corrections saved. The owner will get an email about them.'),
      findsOneWidget,
    );
    expect(await rows(tester, 'corrections'), hasLength(2));
    expect(await rows(tester, 'outbox'), hasLength(1));
  });

  testWidgets('add change stays off when nothing is different', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await scrollToReason(tester);
    await tester.enterText(find.byKey(const Key('reason_field')), 'checking');
    await tester.pump();

    expect(enabled(tester, 'add_change'), isFalse);
  });

  testWidgets('undo change takes it out of the waiting list', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await typeReasonAndAdd(tester, 'typo');
    await tester.tap(find.byKey(const Key('undo_change')));
    await tester.pumpAndSettle();

    expect(find.text('Changed'), findsNothing);
    expect(find.text('End 5 · In 0 · Out 3'), findsOneWidget);
    expect(enabled(tester, 'save_corrections'), isFalse);
  });

  testWidgets('tapping a waiting change again shows what was added', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await typeReasonAndAdd(tester, 'typo');
    await tester.tap(find.byKey(Key('fix_count_$syrupId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('end_field')))
          .controller!
          .text,
      '6',
    );
    expect(find.text('Update change'), findsOneWidget);
  });

  testWidgets('picking another item with an edit not added asks first', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await tester.pump();
    await tester.tap(find.byKey(Key('fix_count_$syrupId')));
    await tester.pumpAndSettle();

    expect(find.text('Discard the change to Fries pack?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    // still on fries with the edit
    expect(find.byKey(const Key('end_field')), findsOneWidget);

    await tester.tap(find.byKey(Key('fix_count_$syrupId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sealed_value')), findsOneWidget);
  });

  testWidgets('cancel with a waiting change asks, then saves nothing', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await typeReasonAndAdd(tester, 'typo');
    await tester.tap(find.byKey(const Key('cancel_corrections')));
    await tester.pumpAndSettle();

    expect(find.text('Discard 1 change?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard_button')));
    await waitForDb(tester);

    // back on history, nothing saved
    expect(find.byKey(const Key('correct_button')), findsOneWidget);
    expect(await rows(tester, 'corrections'), isEmpty);
    expect(await rows(tester, 'outbox'), isEmpty);
  });

  testWidgets('cancel with nothing waiting just closes', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(const Key('cancel_corrections')));
    await waitForDb(tester);

    expect(find.byKey(const Key('correct_button')), findsOneWidget);
  });

  testWidgets('the fix updates the draft Start on the count tab', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await typeReasonAndAdd(tester, 'typo');
    await saveAll(tester);

    late double start;
    await tester.runAsync(() async {
      final draft = await store.loadDraft();
      start = draft.rows
          .firstWhere((row) => row.item.id == friesId)
          .line
          .startQty;
    });
    expect(start, 6);
  });

  testWidgets('no expected number shows', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);
    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();

    expect(find.textContaining('xpected'), findsNothing);
    expect(find.textContaining('gap'), findsNothing);
  });
}
