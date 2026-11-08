import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_line.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/data/submit_store.dart';
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
  late SubmitStore submits;
  late StockItemStore stock;
  late MenuItemStore menu;
  late RecipeStore recipes;
  // fake clock, starts on Nov 1
  late DateTime now;

  late int syrupId;
  late int friesId;
  late int latteId;
  late int friesMenuId;

  setUp(() async {
    db = await openTestDatabase();
    now = DateTime.utc(2026, 11, 1, 10);
    counts = CountStore(db, clock: () => now);
    submits = SubmitStore(db, clock: () => now);
    stock = StockItemStore(db);
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

  // submits the draft on its own date, then the clock moves to the next day
  Future<void> submitDraft() async {
    final day = await draft();
    await submits.submit(day.day.id, date: day.day.businessDate);
    now = now.add(const Duration(days: 1));
  }

  Future<void> tally(int menuId, int times) async {
    final dayId = (await draft()).day.id;
    for (var i = 0; i < times; i++) {
      await counts.tally.add(dayId, menuId);
    }
  }

  // counts the fries with a typed number
  Future<void> countFries(double number) async {
    final row = rowOf(await draft(), friesId);
    await counts.saveNumberCount(row.line.id, number);
  }

  // counts the syrup with sealed and an opened level or exact amount
  Future<void> countSyrup(
    int sealed, {
    double level = levelNone,
    double? exactQty,
  }) async {
    final row = rowOf(await draft(), syrupId);
    await counts.saveContainerCount(
      row,
      sealed: sealed,
      level: level,
      exactQty: exactQty,
    );
  }

  Future<void> finishSyrup() async {
    await counts.finishContainer(rowOf(await draft(), syrupId));
  }

  // the first day of the app, sets the starting stock: 8 fries and syrup as given
  Future<void> openingDay({int sealed = 3, double level = levelNone}) async {
    await countFries(8);
    await countSyrup(sealed, level: level);
    await submitDraft();
  }

  Future<Map<String, Object?>> dayRow(int dayId) async {
    final rows = await db.query(
      'business_days',
      where: 'id = ?',
      whereArgs: [dayId],
    );
    return rows.single;
  }

  Future<Map<String, Object?>> resultOf(int dayId, int itemId) async {
    final rows = await db.query(
      'day_results',
      where: 'day_id = ? AND stock_item_id = ?',
      whereArgs: [dayId, itemId],
    );
    return rows.single;
  }

  Future<List<Map<String, Object?>>> checksOf(int dayId) {
    return db.query(
      'container_checks',
      where: 'day_id = ?',
      whereArgs: [dayId],
    );
  }

  group('locking the day', () {
    test('marks it submitted with the time', () async {
      final dayId = (await draft()).day.id;

      expect(await submits.submit(dayId, date: '2026-11-01'), isTrue);

      final row = await dayRow(dayId);
      expect(row['status'], 'submitted');
      expect(row['submitted_at'], '2026-11-01T10:00:00.000Z');
    });

    test('a double tap only submits once', () async {
      final dayId = (await draft()).day.id;

      final results = await Future.wait([
        submits.submit(dayId, date: '2026-11-01'),
        submits.submit(dayId, date: '2026-11-01'),
      ]);

      expect(results, unorderedEquals([true, false]));
      final saved = await db.query('day_results');
      expect(saved, hasLength(2));
    });

    test('submitting again later changes nothing', () async {
      final dayId = (await draft()).day.id;
      await submits.submit(dayId, date: '2026-11-01');
      now = now.add(const Duration(hours: 3));

      expect(await submits.submit(dayId, date: '2026-11-03'), isFalse);

      final row = await dayRow(dayId);
      expect(row['business_date'], '2026-11-01');
      expect(row['submitted_at'], '2026-11-01T10:00:00.000Z');
    });

    test('an error undoes the whole submit', () async {
      final dayId = (await draft()).day.id;
      await db.execute('DROP TABLE container_checks');
      await db.execute('DROP TABLE day_results');

      await expectLater(
        submits.submit(dayId, date: '2026-11-03', skippedDaysOpen: false),
        throwsA(isA<DatabaseException>()),
      );

      final row = await dayRow(dayId);
      expect(row['status'], 'draft');
      expect(row['business_date'], '2026-11-01');
      expect(row['submitted_at'], isNull);
      expect(await db.query('business_days'), hasLength(1));
    });
  });

  group('dates', () {
    test('the next draft is the day after', () async {
      await submitDraft();

      expect((await draft()).day.businessDate, '2026-11-02');
    });

    test('the same date covers nothing and closes nothing', () async {
      final dayId = (await draft()).day.id;
      await submits.submit(dayId, date: '2026-11-01');

      expect((await dayRow(dayId))['covers_from'], isNull);
      expect(await db.query('business_days'), hasLength(1));
    });

    test('open on the skipped days = the count covers them', () async {
      final dayId = (await draft()).day.id;

      await submits.submit(dayId, date: '2026-11-03');

      final row = await dayRow(dayId);
      expect(row['business_date'], '2026-11-03');
      expect(row['covers_from'], '2026-11-01');
      expect(await db.query('business_days'), hasLength(1));
    });

    test('closed on the skipped days = they are saved as closed', () async {
      final dayId = (await draft()).day.id;

      await submits.submit(dayId, date: '2026-11-03', skippedDaysOpen: false);

      expect((await dayRow(dayId))['covers_from'], isNull);
      final closed = await db.query(
        'business_days',
        where: "status = 'closed'",
        orderBy: 'business_date',
      );
      expect(closed.map((row) => row['business_date']), [
        '2026-11-01',
        '2026-11-02',
      ]);
    });

    test('the next draft comes after a moved date', () async {
      final dayId = (await draft()).day.id;
      await submits.submit(dayId, date: '2026-11-03', skippedDaysOpen: false);

      expect((await draft()).day.businessDate, '2026-11-04');
    });

    test('a date cant go back', () async {
      final dayId = (await draft()).day.id;

      await expectLater(
        submits.submit(dayId, date: '2026-10-31'),
        throwsArgumentError,
      );

      expect((await dayRow(dayId))['status'], 'draft');
    });
  });

  group('results', () {
    test('an opening count sets the stock and shows no usage', () async {
      await countFries(3);
      await tally(friesMenuId, 2);
      final dayId = (await draft()).day.id;

      await submitDraft();

      final result = await resultOf(dayId, friesId);
      expect(result['actual_qty'], isNull);
      expect(result['expected_qty'], isNull);
      expect(result['gap'], isNull);
      // 3 is at or below the level of 5
      expect(result['restock_flag'], 1);
    });

    test('an exact day gets actual, expected and gap', () async {
      await openingDay();
      await countFries(5);
      await tally(friesMenuId, 2);
      final dayId = (await draft()).day.id;

      await submitDraft();

      // 8 at the start - 5 at the end = 3 used, 2 x 1 = 2 expected, 1 more than the tally explains
      final result = await resultOf(dayId, friesId);
      expect(result['actual_qty'], 3);
      expect(result['actual_is_exact'], 1);
      expect(result['expected_qty'], 2);
      expect(result['gap'], 1);
      expect(result['restock_flag'], 1);
    });

    test('a restock counts in the actual', () async {
      await openingDay();
      final row = rowOf(await draft(), friesId);
      await counts.addRestock(row, 10);
      await countFries(15);
      final dayId = (await draft()).day.id;

      await submitDraft();

      // 8 + 10 - 15 = 3
      final result = await resultOf(dayId, friesId);
      expect(result['actual_qty'], 3);
      expect(result['restock_flag'], 0);
    });

    test('a level count shows no gap', () async {
      await openingDay(sealed: 2, level: level50);
      await countSyrup(2, level: level25);
      await tally(latteId, 10);
      final dayId = (await draft()).day.id;

      await submitDraft();

      // 5000 - 4500 = about 500 used, 10 x 30 = 300 expected
      final result = await resultOf(dayId, syrupId);
      expect(result['actual_qty'], 500);
      expect(result['actual_is_exact'], 0);
      expect(result['expected_qty'], 300);
      expect(result['gap'], isNull);
    });

    test('2 menu items using one item add up', () async {
      final mochaId = await menu.add(
        const MenuItem(name: 'Mocha', category: 'Coffee'),
      );
      await recipes.addLine(mochaId, syrupId, 150);
      await openingDay();
      await countSyrup(2, exactQty: 1250);
      await tally(latteId, 5);
      await tally(mochaId, 4);
      final dayId = (await draft()).day.id;

      await submitDraft();

      // 6000 - 5250 = 750 used, 5 x 30 + 4 x 150 = 750 expected
      final result = await resultOf(dayId, syrupId);
      expect(result['actual_qty'], 750);
      expect(result['expected_qty'], 750);
      // syrup is a container item, it never gets a daily gap even with exact counts (rule 7)
      expect(result['gap'], isNull);
    });

    test('in a recipe with nothing tallied expects 0', () async {
      await openingDay();
      await countFries(7);
      final dayId = (await draft()).day.id;

      await submitDraft();

      final result = await resultOf(dayId, friesId);
      expect(result['expected_qty'], 0);
      expect(result['gap'], 1);
    });

    test('in no recipe shows actual only', () async {
      final lines = await recipes.lines(friesMenuId);
      await recipes.removeLine(lines.single.id);
      await openingDay();
      await countFries(7);
      final dayId = (await draft()).day.id;

      await submitDraft();

      final result = await resultOf(dayId, friesId);
      expect(result['actual_qty'], 1);
      expect(result['expected_qty'], isNull);
      expect(result['gap'], isNull);
    });

    test(
      'a recipe amount changed before the submit uses the new one',
      () async {
        await openingDay();
        final lines = await recipes.lines(friesMenuId);
        now = now.add(const Duration(hours: 1));
        await recipes.changeAmount(lines.single.id, 2);
        now = now.add(const Duration(hours: 1));
        await tally(friesMenuId, 3);
        final dayId = (await draft()).day.id;

        await submitDraft();

        // 3 x 2, the old amount of 1 is not added too
        expect((await resultOf(dayId, friesId))['expected_qty'], 6);
      },
    );

    test('an item archived during the day gets no result', () async {
      final oldId = await stock.add(
        const StockItem(
          name: 'Old lids',
          category: 'Packaging',
          baseUnit: BaseUnit.pcs,
          countType: CountType.number,
          lowMode: LowMode.exact,
          lowValue: 0,
        ),
      );
      final dayId = (await draft()).day.id;
      await stock.archive(oldId);

      await submitDraft();

      final rows = await db.query(
        'day_results',
        where: 'stock_item_id = ?',
        whereArgs: [oldId],
      );
      expect(rows, isEmpty);
      expect(
        await db.query('day_results', where: 'day_id = $dayId'),
        hasLength(2),
      );
    });
  });

  group('carry-over', () {
    test('the next draft starts from what was counted', () async {
      await countFries(8);
      await countSyrup(2, level: level50);
      await submitDraft();

      final next = await draft();
      final fries = rowOf(next, friesId).line;
      final bottle = rowOf(next, syrupId).line;
      expect(fries.startQty, 8);
      expect(fries.isOpening, isFalse);
      expect(bottle.startQty, 5000);
      expect(bottle.startIsExact, isFalse);
      expect(bottle.sealed, 2);
      expect(bottle.level, level50);
    });

    test('a restored item stops needing an opening count', () async {
      final lines = await recipes.lines(friesMenuId);
      await recipes.removeLine(lines.single.id);
      await openingDay();
      await stock.archive(friesId);
      await stock.restore(friesId);
      await countFries(4);

      await submitDraft();

      final item = await stock.findByName('Fries pack');
      expect(item!.needsOpeningCount, isFalse);
      final next = rowOf(await draft(), friesId).line;
      expect(next.isOpening, isFalse);
      expect(next.startQty, 4);
    });
  });

  group('review', () {
    test('counts what changed and lists events and notes', () async {
      await openingDay();
      final dayId = (await draft()).day.id;
      await counts.addRestock(rowOf(await draft(), syrupId), 2000);
      await finishSyrup();
      await countFries(5);
      await counts.saveNote(rowOf(await draft(), friesId).line.id, 'dropped 1');
      await counts.saveDayNote(dayId, 'power outage');
      await tally(friesMenuId, 3);

      final review = await submits.review(await draft());

      expect(review.itemsChanged, 2);
      expect(review.tallyTotal, 3);
      expect(review.events.map((event) => event.isRestock), [true, false]);
      expect(review.events.first.qty, 2000);
      expect(review.notes.single.itemName, 'Fries pack');
      expect(review.notes.single.note, 'dropped 1');
      expect(review.dayNote, 'power outage');
      expect(review.hasWarnings, isFalse);
    });

    test('warns about used items not counted yet', () async {
      await openingDay();
      await tally(latteId, 1);

      final review = await submits.review(await draft());

      expect(review.doubleCheckItems, ['Caramel syrup']);
    });

    test('warns about opening counts not counted yet', () async {
      await countFries(8);

      final review = await submits.review(await draft());

      expect(review.openingItems, ['Caramel syrup']);
    });

    test('warns about tallied items with no recipe', () async {
      final soupId = await menu.add(
        const MenuItem(name: 'Soup', category: 'Food'),
      );
      await tally(soupId, 1);

      final review = await submits.review(await draft());

      expect(review.noRecipeItems, ['Soup']);
    });

    test('not compared items never show as no recipe', () async {
      final waffleId = await menu.add(
        const MenuItem(name: 'Waffle', category: 'Food', noStock: true),
      );
      await tally(waffleId, 1);

      final review = await submits.review(await draft());

      expect(review.noRecipeItems, isEmpty);
    });

    test('a tally taken back to 0 is no warning', () async {
      final soupId = await menu.add(
        const MenuItem(name: 'Soup', category: 'Food'),
      );
      await tally(soupId, 1);
      await counts.tally.remove((await draft()).day.id, soupId);

      final review = await submits.review(await draft());

      expect(review.noRecipeItems, isEmpty);
      expect(review.tallyTotal, 0);
    });
  });

  test('restock items are the names flagged that day', () async {
    await countFries(3);
    await countSyrup(4);
    final dayId = (await draft()).day.id;

    await submitDraft();

    expect(await submits.restockItems(dayId), ['Fries pack']);
  });

  test('a day note saves trimmed and clears when empty', () async {
    final dayId = (await draft()).day.id;

    await counts.saveDayNote(dayId, '  power outage  ');
    expect((await draft()).day.dayNote, 'power outage');

    await counts.saveDayNote(dayId, '   ');
    expect((await draft()).day.dayNote, isNull);
  });

  group('container checks', () {
    test('no check when nothing was finished', () async {
      await openingDay();
      await countSyrup(2, level: level50);
      final dayId = (await draft()).day.id;

      await submitDraft();

      expect(await checksOf(dayId), isEmpty);
    });

    test('an opening day gets no check, even with one finished', () async {
      await countSyrup(2, level: level50);
      await finishSyrup();
      final dayId = (await draft()).day.id;

      await submitDraft();

      expect(await checksOf(dayId), isEmpty);
    });

    test('opening at 50% then 2 finished checks, the hand math', () async {
      // day 1: 1 sealed and a bottle at 50%
      await openingDay(sealed: 1, level: level50);

      // day 2: nothing finished, 10 lattes = 300 ml
      await tally(latteId, 10);
      await submitDraft();

      // day 3: the 50% bottle is finished, 20 lattes = 600 ml
      await tally(latteId, 20);
      await finishSyrup();
      final day3 = (await draft()).day.id;
      await submitDraft();

      final first = (await checksOf(day3)).single;
      expect(first['containers'], 1);
      // 50% of 2000 ml, the bottle wasnt full when counting began
      expect(first['container_total'], 1000);
      // 300 + 600
      expect(first['expected_since_last'], 900);
      expect(first['since_date'], '2026-11-01');

      // day 4: the last bottle is finished, 40 lattes = 1200 ml
      await tally(latteId, 40);
      await finishSyrup();
      final day4 = (await draft()).day.id;
      await submitDraft();

      final second = (await checksOf(day4)).single;
      expect(second['containers'], 1);
      expect(second['container_total'], 2000);
      // only day 4, day 3 was already in the first check
      expect(second['expected_since_last'], 1200);
      expect(second['since_date'], '2026-11-03');
    });

    test('a typed exact amount at the opening count works too', () async {
      await countSyrup(1, exactQty: 640);
      await submitDraft();
      await finishSyrup();
      final dayId = (await draft()).day.id;

      await submitDraft();

      expect((await checksOf(dayId)).single['container_total'], 640);
    });

    test('an item in no recipe reports with no expected', () async {
      final lines = await recipes.lines(latteId);
      await recipes.removeLine(lines.single.id);
      await openingDay(sealed: 2, level: level50);
      await finishSyrup();
      final dayId = (await draft()).day.id;

      await submitDraft();

      final check = (await checksOf(dayId)).single;
      expect(check['container_total'], 1000);
      expect(check['expected_since_last'], isNull);
    });
  });
}
