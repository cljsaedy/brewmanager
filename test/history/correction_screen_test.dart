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

  Future<void> typeReasonAndSave(WidgetTester tester, String reason) async {
    // the form can be taller than the screen, a list only builds what is on screen
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
    await tester.enterText(find.byKey(const Key('reason_field')), reason);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('save_correction')));
    await tester.tap(find.byKey(const Key('save_correction')));
    await waitForDb(tester);
  }

  bool saveEnabled(WidgetTester tester) {
    return tester
        .widget<FilledButton>(find.byKey(const Key('save_correction')))
        .enabled;
  }

  testWidgets('correct shows only on the newest submitted day', (tester) async {
    await tester.runAsync(addDays);
    await openHistory(tester);

    expect(find.byKey(const Key('correct_button')), findsOneWidget);

    await tester.tap(find.text('Sun, Nov 1').first);
    await waitForDb(tester);

    expect(find.byKey(const Key('correct_button')), findsNothing);
  });

  testWidgets('a number End fix needs a reason, then shows in history', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);

    await typeReasonAndSave(tester, 'typo');

    expect(
      find.text('Correction saved. The owner will get an email about it.'),
      findsOneWidget,
    );
    expect(find.text('End 6 · In 0 · Out 2'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await waitForDb(tester);
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
    await typeReasonAndSave(tester, 'missed one');

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

  testWidgets('a tally fix and a day note fix', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_tally_$friesMenuId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty_plus')));
    await tester.pump();
    await typeReasonAndSave(tester, 'missed a receipt');
    expect(find.text('× 3'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('fix_dayNote_0')));
    await tester.tap(find.byKey(const Key('fix_dayNote_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('day_note_field')),
      'power outage',
    );
    await typeReasonAndSave(tester, 'forgot');

    late List<Map<String, Object?>> emails;
    await tester.runAsync(() async => emails = await db.query('outbox'));
    expect(emails, hasLength(2));
  });

  testWidgets('saving with nothing changed says so', (tester) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await typeReasonAndSave(tester, 'just checking');

    expect(find.text('Nothing changed, so nothing was saved.'), findsOneWidget);
  });

  testWidgets('the fix updates the draft Start on the count tab', (
    tester,
  ) async {
    await tester.runAsync(addDays);
    await openCorrect(tester);

    await tester.tap(find.byKey(Key('fix_count_$friesId')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('end_field')), '6');
    await typeReasonAndSave(tester, 'typo');
    await tester.tap(find.text('Done'));
    await waitForDb(tester);

    late Map<String, Object?> line;
    await tester.runAsync(() async {
      final draft = await store.loadDraft();
      line = {
        'start': draft.rows
            .firstWhere((row) => row.item.id == friesId)
            .line
            .startQty,
      };
    });
    expect(line['start'], 6);
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
