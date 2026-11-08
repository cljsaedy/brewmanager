import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/correction_store.dart';
import 'package:brewmanager/data/count_line.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/count_math.dart';
import 'package:brewmanager/logic/units.dart';

import '../helpers/test_database.dart';

// a 2000 ml bottle item, low at 1 bottle
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
  late CountStore counts;
  late CorrectionStore fixes;
  late RecipeStore recipes;
  late MenuItemStore menu;
  // fake clock, starts on nov 1
  late DateTime now;

  late int syrupId;
  late int friesId;
  late int latteId;
  late int friesMenuId;

  setUp(() async {
    db = await openTestDatabase();
    now = DateTime.utc(2026, 11, 1, 10);
    counts = CountStore(db, clock: () => now);
    fixes = counts.corrections;
    final stock = StockItemStore(db);
    menu = MenuItemStore(db, clock: () => now);
    recipes = RecipeStore(db, clock: () => now);

    syrupId = await stock.add(syrup);
    friesId = await stock.add(friesPack);
    latteId = await menu.add(const MenuItem(name: 'Latte', category: 'Coffee'));
    friesMenuId = await menu.add(
      const MenuItem(name: 'French Fries', category: 'Food'),
    );
    // a latte uses 30 ml of syrup, french fries use 1 fries pack
    await recipes.addLine(latteId, syrupId, 30);
    await recipes.addLine(friesMenuId, friesId, 1);
  });

  tearDown(() async {
    await db.close();
  });

  Future<DraftDay> draft() => counts.loadDraft();

  CountRow rowOf(DraftDay day, int itemId) {
    return day.rows.firstWhere((row) => row.item.id == itemId);
  }

  // submits the draft on its own date, gives back its id, then the clock moves a day
  Future<int> submitDraft() async {
    final day = await draft();
    await counts.submits.submit(day.day.id, date: day.day.businessDate);
    now = now.add(const Duration(days: 1));
    return day.day.id;
  }

  Future<void> tally(int menuId, int times) async {
    final dayId = (await draft()).day.id;
    for (var i = 0; i < times; i++) {
      await counts.tally.add(dayId, menuId);
    }
  }

  Future<void> countFries(double number) async {
    await counts.saveNumberCount(rowOf(await draft(), friesId).line.id, number);
  }

  Future<void> countSyrup(int sealed, double level) async {
    await counts.saveContainerCount(
      rowOf(await draft(), syrupId),
      sealed: sealed,
      level: level,
      exactQty: null,
    );
  }

  // day 1 (nov 1): opening count, 8 fries and syrup at 2 sealed + 50%
  // day 2 (nov 2): 5 fries left, 2 french fries tallied, syrup at 2 sealed + 25%
  // gives back day 2's id
  Future<int> twoDays() async {
    await countFries(8);
    await countSyrup(2, level50);
    await submitDraft();
    await countFries(5);
    await countSyrup(2, level25);
    await tally(friesMenuId, 2);
    return submitDraft();
  }

  // the fix for fries with everything as it is, change only what a test needs
  CountFix friesFix({double number = 5, double inQty = 0, String? note}) {
    return CountFix(number: number, inQty: inQty, outCount: 0, note: note);
  }

  CountFix syrupFix({
    int sealed = 2,
    double level = level25,
    double? exactQty,
    double inQty = 0,
    int outCount = 0,
  }) {
    return CountFix(
      sealed: sealed,
      level: level,
      exactQty: exactQty,
      inQty: inQty,
      outCount: outCount,
    );
  }

  Future<Map<String, Object?>> resultOf(int dayId, int itemId) async {
    final rows = await db.query(
      'day_results',
      where: 'day_id = ? AND stock_item_id = ?',
      whereArgs: [dayId, itemId],
    );
    return rows.single;
  }

  // only the correction emails, every submit queues a daily email too
  Future<List<Map<String, Object?>>> correctionEmails() {
    return db.query('outbox', where: "kind = 'correction'");
  }

  Future<CountLine> lineOf(int dayId, int itemId) async {
    final rows = await db.query(
      'count_lines',
      where: 'day_id = ? AND stock_item_id = ?',
      whereArgs: [dayId, itemId],
    );
    return CountLine.fromRow(rows.single);
  }

  group('which day', () {
    test('nothing to correct before the first submit', () async {
      await draft();

      expect(await fixes.correctableDayId(), isNull);
    });

    test('only the newest submitted day', () async {
      await countFries(8);
      final day1 = await submitDraft();
      expect(await fixes.correctableDayId(), day1);

      final day2 = await submitDraft();
      expect(await fixes.correctableDayId(), day2);
    });

    test('an older day is final, the store refuses it too', () async {
      await countFries(8);
      final day1 = await submitDraft();
      await submitDraft();

      await expectLater(
        fixes.correctCount(day1, friesId, friesFix(number: 9), 'typo'),
        throwsStateError,
      );
      expect((await lineOf(day1, friesId)).endQty, 8);
      expect(await db.query('corrections'), isEmpty);
    });
  });

  group('rules for every fix', () {
    test('a reason is needed', () async {
      final day2 = await twoDays();

      expect(
        () => fixes.correctCount(day2, friesId, friesFix(number: 6), '   '),
        throwsArgumentError,
      );
      expect(await db.query('corrections'), isEmpty);
    });

    test('no change saves and sends nothing', () async {
      final day2 = await twoDays();

      final changed = await fixes.correctCount(
        day2,
        friesId,
        friesFix(),
        'checking',
      );

      expect(changed, isFalse);
      expect(await db.query('corrections'), isEmpty);
      expect(await correctionEmails(), isEmpty);
    });

    test('an error undoes the whole fix', () async {
      final day2 = await twoDays();
      await db.execute('DROP TABLE outbox');

      await expectLater(
        fixes.correctCount(day2, friesId, friesFix(number: 6), 'typo'),
        throwsA(isA<DatabaseException>()),
      );

      expect((await lineOf(day2, friesId)).endQty, 5);
      expect(await db.query('corrections'), isEmpty);
      expect((await resultOf(day2, friesId))['actual_qty'], 3);
    });
  });

  group('End', () {
    test('logs it, works the day out again and queues an email', () async {
      final day2 = await twoDays();
      // before: 8 - 5 = 3 used, 2 expected, gap 1
      expect((await resultOf(day2, friesId))['gap'], 1);

      final changed = await fixes.correctCount(
        day2,
        friesId,
        friesFix(number: 6),
        'typo',
      );

      expect(changed, isTrue);
      final log = (await db.query('corrections')).single;
      expect(log['target'], 'count');
      expect(log['field'], 'end');
      expect(log['old_value'], '5');
      expect(log['new_value'], '6');
      expect(log['reason'], 'typo');
      expect(log['corrected_at'], '2026-11-03T10:00:00.000Z');

      // after: 8 - 6 = 2 used, 2 expected, gap 0
      final result = await resultOf(day2, friesId);
      expect(result['actual_qty'], 2);
      expect(result['gap'], 0);

      final email = (await correctionEmails()).single;
      expect(email['kind'], 'correction');
      expect(email['day_id'], day2);
      expect(email['status'], 'queued');
      expect(email['subject'], 'Correction on Mon, Nov 2');
      final body = email['html_body'] as String;
      expect(body, contains('Fries pack End 5 → 6 pcs. Reason: typo.'));
      // the corrected count table is in it
      expect(body, contains('Corrected count</h3>'));
      expect(body, contains('>Fries pack</td>'));
    });

    test('a container End shows in containers', () async {
      final day2 = await twoDays();

      await fixes.correctCount(
        day2,
        syrupId,
        syrupFix(sealed: 3),
        'missed one',
      );

      final body = (await correctionEmails()).single['html_body'] as String;
      // 2 sealed + 25% = 2.25, 3 sealed + 25% = 3.25
      expect(body, contains('Caramel syrup End 2.25 → 3.25 bottles.'));
    });

    test('an untouched draft line gets the new Start and End', () async {
      final day2 = await twoDays();
      await draft();

      await fixes.correctCount(day2, friesId, friesFix(number: 6), 'typo');

      final next = rowOf(await draft(), friesId).line;
      expect(next.startQty, 6);
      expect(next.endQty, 6);
    });

    test('a restock already in the draft is kept', () async {
      final day2 = await twoDays();
      await counts.addRestock(rowOf(await draft(), friesId), 10);

      await fixes.correctCount(day2, friesId, friesFix(number: 6), 'typo');

      final next = rowOf(await draft(), friesId);
      expect(next.line.startQty, 6);
      // 6 + the restock of 10
      expect(next.line.endQty, 16);
      expect(next.line.inQty, 10);
      expect(next.restocks, hasLength(1));
    });

    test('a draft line the barista counted keeps its End', () async {
      final day2 = await twoDays();
      await countFries(3);

      await fixes.correctCount(day2, friesId, friesFix(number: 6), 'typo');

      final next = rowOf(await draft(), friesId).line;
      expect(next.startQty, 6);
      expect(next.endQty, 3);
    });

    test('a typed exact End keeps the next Start exact', () async {
      final day2 = await twoDays();
      await draft();

      await fixes.correctCount(
        day2,
        syrupId,
        syrupFix(sealed: 2, level: levelNone, exactQty: 300),
        'measured it',
      );

      final next = rowOf(await draft(), syrupId).line;
      expect(next.startQty, 4300);
      expect(next.startIsExact, isTrue);
      expect(next.exactQty, 300);
    });

    test('finished taps and restocks in the draft are done again', () async {
      final day2 = await twoDays();
      // today: 1 bottle finished (2 sealed + 25% -> 1 sealed + full), then 1 bottle in
      await counts.finishContainer(rowOf(await draft(), syrupId));
      await counts.addRestock(rowOf(await draft(), syrupId), 2000);

      // last night was really 1 sealed + 75%
      await fixes.correctCount(
        day2,
        syrupId,
        syrupFix(sealed: 1, level: level75),
        'miscounted',
      );

      // 1 sealed + 75% -> finished -> 0 sealed + full -> restock -> 1 sealed + full
      final next = rowOf(await draft(), syrupId).line;
      expect(next.startQty, 3500);
      expect(next.sealed, 1);
      expect(next.level, levelFull);
      expect(next.endQty, 4000);
      expect(next.outCount, 1);
      expect(next.touched, isFalse);

      // undo still knows what the finished tap changed
      await counts.undoFinish(rowOf(await draft(), syrupId));
      final undone = rowOf(await draft(), syrupId).line;
      // back to 1 sealed + 75%, plus the restock
      expect(undone.sealed, 2);
      expect(undone.level, level75);
    });
  });

  group('In, Out and notes', () {
    test('In changes the usage but not End or the draft', () async {
      final day2 = await twoDays();
      await draft();

      await fixes.correctCount(
        day2,
        friesId,
        friesFix(inQty: 4),
        'forgot the delivery',
      );

      // 8 + 4 - 5 = 7 used
      expect((await resultOf(day2, friesId))['actual_qty'], 7);
      expect((await lineOf(day2, friesId)).endQty, 5);
      final next = rowOf(await draft(), friesId).line;
      expect(next.startQty, 5);
      final log = (await db.query('corrections')).single;
      expect(log['field'], 'in');
    });

    test('Out makes a container check', () async {
      final day2 = await twoDays();
      expect(
        await db.query('container_checks', where: 'day_id = $day2'),
        isEmpty,
      );

      await fixes.correctCount(
        day2,
        syrupId,
        syrupFix(outCount: 1),
        'forgot to tap finished',
      );

      final check = (await db.query(
        'container_checks',
        where: 'day_id = $day2',
      )).single;
      // the first check after an opening count at 50%
      expect(check['container_total'], 1000);
    });

    test('an item note and the day note are logged', () async {
      final day2 = await twoDays();

      await fixes.correctCount(
        day2,
        friesId,
        friesFix(note: '  1 pack dropped  '),
        'forgot the note',
      );
      await fixes.correctDayNote(day2, 'power outage at 3pm', 'forgot');

      expect((await lineOf(day2, friesId)).note, '1 pack dropped');
      final entries = await fixes.corrections(day2);
      expect(entries.map((entry) => entry.description), [
        'Fries pack note (none) → “1 pack dropped”',
        'Day note (none) → “power outage at 3pm”',
      ]);
      expect(await correctionEmails(), hasLength(2));
    });

    test('changing several fields logs each one', () async {
      final day2 = await twoDays();

      await fixes.correctCount(
        day2,
        friesId,
        friesFix(number: 6, inQty: 2, note: 'x'),
        'fixing',
      );

      final fields = (await db.query(
        'corrections',
        orderBy: 'id',
      )).map((row) => row['field']);
      expect(fields, ['end', 'in', 'note']);
      // still 1 email for 1 fix
      expect(await correctionEmails(), hasLength(1));
    });
  });

  group('tally', () {
    test('a new quantity changes expected', () async {
      final day2 = await twoDays();

      await fixes.correctTally(day2, friesMenuId, 3, 'missed a receipt');

      // 3 x 1 expected, 3 used, gap 0
      final result = await resultOf(day2, friesId);
      expect(result['expected_qty'], 3);
      expect(result['gap'], 0);
      final entries = await fixes.corrections(day2);
      expect(entries.single.description, 'French Fries tally 2 → 3');
    });

    test('a menu item not tallied that day can be added', () async {
      final day2 = await twoDays();

      await fixes.correctTally(day2, latteId, 10, 'missed a page');

      // 10 x 30 ml
      expect((await resultOf(day2, syrupId))['expected_qty'], 300);
    });

    test('the same quantity changes nothing', () async {
      final day2 = await twoDays();

      expect(await fixes.correctTally(day2, friesMenuId, 2, 'x'), isFalse);
      expect(await correctionEmails(), isEmpty);
    });

    test('the recipes from the submit are used, not new ones', () async {
      final day2 = await twoDays();
      final line = (await recipes.lines(friesMenuId)).single;
      await recipes.changeAmount(line.id, 5);

      await fixes.correctTally(day2, friesMenuId, 3, 'missed a receipt');

      // still 1 pack each from when day 2 was submitted
      expect((await resultOf(day2, friesId))['expected_qty'], 3);
    });
  });

  group('saving several at once', () {
    test('every change is logged and the owner gets 1 email', () async {
      final day2 = await twoDays();

      final changed = await fixes.saveAll(day2, [
        CountCorrection(friesId, friesFix(number: 6), 'typo'),
        TallyCorrection(friesMenuId, 3, 'missed a receipt'),
        const DayNoteCorrection('power outage', 'forgot'),
      ]);

      expect(changed, 3);
      expect((await lineOf(day2, friesId)).endQty, 6);
      final entries = await fixes.corrections(day2);
      expect(entries.map((entry) => entry.reason), [
        'typo',
        'missed a receipt',
        'forgot',
      ]);
      final emails = await correctionEmails();
      expect(emails, hasLength(1));
      final html = emails.single['html_body'] as String;
      expect(html, contains('Fries pack End 5 → 6 pcs'));
      expect(html, contains('French Fries tally 2 → 3'));
      expect(html, contains('power outage'));
      // 6 fries left from 8, 3 tallied: actual 2, expected 3
      expect((await resultOf(day2, friesId))['actual_qty'], 2);
      expect((await resultOf(day2, friesId))['expected_qty'], 3);
    });

    test('a change that is the same as saved is skipped', () async {
      final day2 = await twoDays();

      final changed = await fixes.saveAll(day2, [
        CountCorrection(friesId, friesFix(), 'checking'),
        const DayNoteCorrection('power outage', 'forgot'),
      ]);

      expect(changed, 1);
      expect(await db.query('corrections'), hasLength(1));
    });

    test('nothing changed saves and sends nothing', () async {
      final day2 = await twoDays();

      expect(
        await fixes.saveAll(day2, [
          CountCorrection(friesId, friesFix(), 'checking'),
        ]),
        0,
      );
      expect(await correctionEmails(), isEmpty);
    });

    test('an error in 1 change undoes all of them', () async {
      final day2 = await twoDays();

      // menu item 999 does not exist, so its tally line breaks the foreign key
      await expectLater(
        fixes.saveAll(day2, [
          CountCorrection(friesId, friesFix(number: 6), 'typo'),
          TallyCorrection(999, 3, 'bad'),
        ]),
        throwsA(isA<DatabaseException>()),
      );

      expect((await lineOf(day2, friesId)).endQty, 5);
      expect(await db.query('corrections'), isEmpty);
      expect(await correctionEmails(), isEmpty);
    });

    test('1 missing reason stops all of them before anything starts', () async {
      final day2 = await twoDays();

      expect(
        () => fixes.saveAll(day2, [
          CountCorrection(friesId, friesFix(number: 6), 'typo'),
          const DayNoteCorrection('x', ' '),
        ]),
        throwsArgumentError,
      );
      expect((await lineOf(day2, friesId)).endQty, 5);
    });
  });

  test('diffCount sees a level change even when End stays the same', () {
    const old = CountLine(
      id: 1,
      dayId: 1,
      stockItemId: 1,
      startQty: 0,
      startIsExact: true,
      inQty: 0,
      outCount: 0,
      sealed: 1,
      level: levelNone,
      exactQty: 500,
      endQty: 2500,
      endIsExact: true,
      touched: true,
      isOpening: false,
      note: null,
    );
    // 1 sealed + 25% of 2000 = 2500 too, but now it is an estimate
    final diff = diffCount(
      syrup,
      old,
      const CountFix(sealed: 1, level: level25, inQty: 0, outCount: 0),
    );

    expect(diff.end, 2500);
    expect(diff.countChanged, isTrue);
    expect(diff.endIsExact, isFalse);
    expect(diff.any, isTrue);
  });
}
