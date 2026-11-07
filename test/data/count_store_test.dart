import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

// a 2000 ml bottle item
StockItem syrup({String name = 'Caramel syrup', String category = 'Syrups'}) {
  return StockItem(
    name: name,
    category: category,
    baseUnit: BaseUnit.ml,
    countType: CountType.container,
    containerLabel: 'bottle',
    containerSize: 2000,
    lowMode: LowMode.containers,
    lowValue: 1,
  );
}

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
  late StockItemStore stock;
  // fake clock, tests move it forward to get known times
  late DateTime now;

  setUp(() async {
    db = await openTestDatabase();
    now = DateTime(2026, 11, 1, 10).toUtc();
    store = CountStore(db, clock: () => now);
    stock = StockItemStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // adds a submitted (or closed) day straight in the db, feature 7 makes these for real
  Future<int> addDay(String date, {String status = 'submitted'}) {
    return db.insert('business_days', {
      'business_date': date,
      'status': status,
    });
  }

  // adds a count line straight in the db, like one saved by a submit
  Future<void> addLine(
    int dayId,
    int stockItemId, {
    required double end,
    bool endIsExact = true,
    int? sealed,
    double? level,
    double? exact,
  }) {
    return db.insert('count_lines', {
      'day_id': dayId,
      'stock_item_id': stockItemId,
      'end_qty': end,
      'end_is_exact': endIsExact ? 1 : 0,
      'sealed': sealed,
      'level': level,
      'exact_qty': exact,
    });
  }

  CountLine lineOf(DraftDay draft, String name) {
    return draft.rows.firstWhere((row) => row.item.name == name).line;
  }

  group('the draft day', () {
    test('the very first draft is dated today on the tablet', () async {
      final draft = await store.loadDraft();

      expect(draft.day.businessDate, '2026-11-01');
      expect(draft.day.status, 'draft');
    });

    test('loading again gives the same draft, no new lines', () async {
      await stock.add(syrup());
      final first = await store.loadDraft();
      final second = await store.loadDraft();

      expect(second.day.id, first.day.id);
      expect(await db.query('business_days'), hasLength(1));
      expect(await db.query('count_lines'), hasLength(1));
    });

    test('the date stays the same after midnight until submit', () async {
      await store.loadDraft();

      now = now.add(const Duration(days: 3));
      expect((await store.loadDraft()).day.businessDate, '2026-11-01');
    });

    test('the next draft is the day after the last submitted day', () async {
      await addDay('2026-10-30');
      expect((await store.loadDraft()).day.businessDate, '2026-10-31');
    });

    test('the month rolls over', () async {
      await addDay('2026-10-31');
      expect((await store.loadDraft()).day.businessDate, '2026-11-01');
    });

    test('closed days count too, a date never repeats', () async {
      await addDay('2026-10-28');
      await addDay('2026-10-29', status: 'closed');
      expect((await store.loadDraft()).day.businessDate, '2026-10-30');
    });
  });

  group('new items', () {
    test('a never counted container item starts empty and exact', () async {
      await stock.add(syrup());
      final line = lineOf(await store.loadDraft(), 'Caramel syrup');

      expect(line.startQty, 0);
      expect(line.startIsExact, isTrue);
      expect(line.sealed, 0);
      expect(line.level, levelNone);
      expect(line.exactQty, isNull);
      expect(line.endQty, 0);
      expect(line.endIsExact, isTrue);
      expect(line.touched, isFalse);
    });

    test('a never counted number item has no container fields', () async {
      await stock.add(friesPack);
      final line = lineOf(await store.loadDraft(), 'Fries pack');

      expect(line.sealed, isNull);
      expect(line.level, isNull);
      expect(line.endQty, 0);
      expect(line.endIsExact, isTrue);
    });

    test('an item added during the day joins the draft', () async {
      await stock.add(syrup());
      await store.loadDraft();

      await stock.add(friesPack);
      expect((await store.loadDraft()).rows, hasLength(2));
    });

    test('rows go by category, then name, ignoring case', () async {
      await stock.add(syrup(name: 'vanilla syrup'));
      await stock.add(syrup(name: 'Caramel syrup', category: 'syrups'));
      await stock.add(syrup(name: 'Whole milk', category: 'Dairy'));

      final draft = await store.loadDraft();
      expect(draft.rows.map((row) => row.item.name), [
        'Whole milk',
        'Caramel syrup',
        'vanilla syrup',
      ]);
    });

    test('archived items are not in the draft', () async {
      final id = await stock.add(syrup());
      await stock.archive(id);

      expect((await store.loadDraft()).rows, isEmpty);
    });

    test('an item archived during the day is hidden, its line stays', () async {
      final id = await stock.add(syrup());
      await store.loadDraft();
      await stock.archive(id);

      expect((await store.loadDraft()).rows, isEmpty);
      expect(await db.query('count_lines'), hasLength(1));
    });
  });

  group('carry-over', () {
    test('sealed, level and an estimated End carry to the draft', () async {
      final id = await stock.add(syrup());
      final day = await addDay('2026-10-31');
      await addLine(
        day,
        id,
        end: 5000,
        endIsExact: false,
        sealed: 2,
        level: level50,
      );

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.startQty, 5000);
      expect(line.startIsExact, isFalse);
      expect(line.sealed, 2);
      expect(line.level, level50);
      expect(line.exactQty, isNull);
      // nobody touched it yet, End starts the same as last night
      expect(line.endQty, 5000);
      expect(line.endIsExact, isFalse);
      expect(line.touched, isFalse);
    });

    test('an exact amount carries and stays exact', () async {
      final id = await stock.add(syrup());
      final day = await addDay('2026-10-31');
      await addLine(day, id, end: 2350, sealed: 1, level: level75, exact: 350);

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.startIsExact, isTrue);
      expect(line.exactQty, 350);
      expect(line.endQty, 2350);
      expect(line.endIsExact, isTrue);
    });

    test('a number item carries its number', () async {
      final id = await stock.add(friesPack);
      final day = await addDay('2026-10-31');
      await addLine(day, id, end: 12);

      final line = lineOf(await store.loadDraft(), 'Fries pack');
      expect(line.startQty, 12);
      expect(line.endQty, 12);
      expect(line.sealed, isNull);
    });

    test('it uses the newest submitted day', () async {
      final id = await stock.add(friesPack);
      await addLine(await addDay('2026-10-29'), id, end: 12);
      await addLine(await addDay('2026-10-30'), id, end: 7);
      await addDay('2026-10-31', status: 'closed');

      expect(lineOf(await store.loadDraft(), 'Fries pack').startQty, 7);
    });

    test(
      'an item missing from the last day continues from its last count',
      () async {
        final id = await stock.add(friesPack);
        await addLine(await addDay('2026-10-20'), id, end: 9);
        await addDay('2026-10-31');

        expect(lineOf(await store.loadDraft(), 'Fries pack').startQty, 9);
      },
    );
  });

  group('opening count', () {
    test('a never counted item is an opening count', () async {
      await stock.add(friesPack);
      expect(lineOf(await store.loadDraft(), 'Fries pack').isOpening, isTrue);
    });

    test('an item counted before is not', () async {
      final id = await stock.add(friesPack);
      await addLine(await addDay('2026-10-31'), id, end: 12);

      expect(lineOf(await store.loadDraft(), 'Fries pack').isOpening, isFalse);
    });

    test('a restored item starts at 0, its old count is ignored', () async {
      final id = await stock.add(syrup());
      final day = await addDay('2026-10-31');
      await addLine(
        day,
        id,
        end: 5000,
        endIsExact: false,
        sealed: 2,
        level: level50,
      );
      await stock.archive(id);
      await stock.restore(id);

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.isOpening, isTrue);
      expect(line.startQty, 0);
      expect(line.startIsExact, isTrue);
      expect(line.sealed, 0);
      expect(line.level, levelNone);
      expect(line.exactQty, isNull);
      expect(line.endQty, 0);
    });

    test('restored during the day, the waiting line starts over', () async {
      final id = await stock.add(syrup());
      final day = await addDay('2026-10-31');
      await addLine(day, id, end: 4000, sealed: 2, level: levelNone);
      expect(lineOf(await store.loadDraft(), 'Caramel syrup').startQty, 4000);

      await stock.archive(id);
      await stock.restore(id);

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.isOpening, isTrue);
      expect(line.startQty, 0);
      expect(line.sealed, 0);
      expect(line.endQty, 0);
    });

    test('restored during the day, a worked line keeps its count', () async {
      final id = await stock.add(syrup());
      final day = await addDay('2026-10-31');
      await addLine(day, id, end: 4000, sealed: 2, level: levelNone);
      final draft = await store.loadDraft();
      // the barista counted 3 bottles, the real save comes in step 4c
      await db.update(
        'count_lines',
        {'sealed': 3, 'end_qty': 6000, 'touched': 1},
        where: 'id = ?',
        whereArgs: [lineOf(draft, 'Caramel syrup').id],
      );

      await stock.archive(id);
      await stock.restore(id);

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.isOpening, isTrue);
      expect(line.startQty, 0);
      expect(line.sealed, 3);
      expect(line.endQty, 6000);
      expect(line.touched, isTrue);
    });

    test('loading again changes nothing on an opening line', () async {
      final id = await stock.add(syrup());
      await addLine(await addDay('2026-10-31'), id, end: 4000, sealed: 2);
      await stock.archive(id);
      await stock.restore(id);
      final first = await store.loadDraft();
      final second = await store.loadDraft();

      final before = lineOf(first, 'Caramel syrup');
      final after = lineOf(second, 'Caramel syrup');
      expect(after.id, before.id);
      expect(after.isOpening, isTrue);
      expect(await db.query('count_lines'), hasLength(2));
    });
  });

  group('autosave', () {
    test('sealed and a level give an estimated End', () async {
      await stock.add(syrup());
      final draft = await store.loadDraft();

      await store.saveContainerCount(
        draft.rows.single,
        sealed: 2,
        level: level50,
        exactQty: null,
      );

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.sealed, 2);
      expect(line.level, level50);
      expect(line.endQty, 5000);
      expect(line.endIsExact, isFalse);
      expect(line.touched, isTrue);
    });

    test('an exact amount replaces the level and is exact', () async {
      await stock.add(syrup());
      final draft = await store.loadDraft();

      await store.saveContainerCount(
        draft.rows.single,
        sealed: 1,
        level: level75,
        exactQty: 350,
      );

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.endQty, 2350);
      expect(line.endIsExact, isTrue);
    });

    test('saving the same values still marks the line touched', () async {
      await stock.add(syrup());
      final draft = await store.loadDraft();
      final line = draft.rows.single.line;
      expect(line.touched, isFalse);

      await store.saveContainerCount(
        draft.rows.single,
        sealed: line.sealed!,
        level: line.level!,
        exactQty: line.exactQty,
      );

      expect(lineOf(await store.loadDraft(), 'Caramel syrup').touched, isTrue);
    });

    test('a number item saves its number as an exact End', () async {
      await stock.add(friesPack);
      final draft = await store.loadDraft();

      await store.saveNumberCount(draft.rows.single.line.id, 9);

      final line = lineOf(await store.loadDraft(), 'Fries pack');
      expect(line.endQty, 9);
      expect(line.endIsExact, isTrue);
      expect(line.touched, isTrue);
    });

    test('a note saves and leaves the line untouched', () async {
      await stock.add(friesPack);
      final draft = await store.loadDraft();

      await store.saveNote(draft.rows.single.line.id, ' 2 packs expired ');

      final line = lineOf(await store.loadDraft(), 'Fries pack');
      expect(line.note, '2 packs expired');
      expect(line.touched, isFalse);
    });

    test('an empty note is saved as null', () async {
      await stock.add(friesPack);
      final draft = await store.loadDraft();
      final id = draft.rows.single.line.id;

      await store.saveNote(id, 'something');
      await store.saveNote(id, '   ');

      expect(lineOf(await store.loadDraft(), 'Fries pack').note, isNull);
    });

    test('the low-stock level saves on the item, line untouched', () async {
      await stock.add(syrup());
      final draft = await store.loadDraft();

      await store.saveLowValue(draft.rows.single.item.id!, 3);

      final row = (await store.loadDraft()).rows.single;
      expect(row.item.lowValue, 3);
      expect(row.item.lowMode, LowMode.containers);
      expect(row.line.touched, isFalse);
    });
  });

  group('restocks', () {
    CountRow rowOf(DraftDay draft, String name) {
      return draft.rows.firstWhere((row) => row.item.name == name);
    }

    test('a container restock adds to sealed, In and End', () async {
      await stock.add(syrup());
      final row = rowOf(await store.loadDraft(), 'Caramel syrup');

      await store.addRestock(row, 4000);

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.sealed, 2);
      expect(line.inQty, 4000);
      expect(line.endQty, 4000);
    });

    test('a number restock adds to the number', () async {
      await stock.add(friesPack);
      final row = rowOf(await store.loadDraft(), 'Fries pack');
      await store.saveNumberCount(row.line.id, 3);

      final saved = await store.addRestock(row, 5);

      expect(saved.endQty, 8);
      expect(saved.inQty, 5);
      expect(saved.endIsExact, isTrue);
    });

    test('a restock keeps the opened part and stays untouched', () async {
      await stock.add(syrup());
      final row = rowOf(await store.loadDraft(), 'Caramel syrup');
      await store.addRestock(row, 2000);
      var line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.touched, isFalse);

      await store.saveContainerCount(
        rowOf(await store.loadDraft(), 'Caramel syrup'),
        sealed: 1,
        level: level50,
        exactQty: null,
      );
      await store.addRestock(row, 2000);

      line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.sealed, 2);
      expect(line.level, level50);
      expect(line.endQty, 5000);
      expect(line.endIsExact, isFalse);
    });

    test('each restock is its own event with its time, oldest first', () async {
      await stock.add(syrup());
      final row = rowOf(await store.loadDraft(), 'Caramel syrup');

      await store.addRestock(row, 2000);
      now = now.add(const Duration(hours: 2));
      await store.addRestock(row, 4000);

      final restocks = rowOf(await store.loadDraft(), 'Caramel syrup').restocks;
      expect(restocks.map((restock) => restock.qty), [2000, 4000]);
      expect(restocks.last.time, now.toLocal());
      expect(lineOf(await store.loadDraft(), 'Caramel syrup').inQty, 6000);
    });

    test('restocks stay with their own item', () async {
      await stock.add(syrup());
      await stock.add(friesPack);
      final draft = await store.loadDraft();

      await store.addRestock(rowOf(draft, 'Fries pack'), 5);

      final after = await store.loadDraft();
      expect(rowOf(after, 'Caramel syrup').restocks, isEmpty);
      expect(rowOf(after, 'Fries pack').restocks, hasLength(1));
    });

    test('removing a restock reverses it', () async {
      await stock.add(syrup());
      final row = rowOf(await store.loadDraft(), 'Caramel syrup');
      await store.addRestock(row, 2000);
      await store.addRestock(row, 4000);

      final first = rowOf(
        await store.loadDraft(),
        'Caramel syrup',
      ).restocks.first;
      await store.removeRestock(row, first);

      final after = rowOf(await store.loadDraft(), 'Caramel syrup');
      expect(after.restocks.single.qty, 4000);
      expect(after.line.sealed, 2);
      expect(after.line.inQty, 4000);
      expect(after.line.endQty, 4000);
    });

    test('removing a number restock takes it off the number', () async {
      await stock.add(friesPack);
      final row = rowOf(await store.loadDraft(), 'Fries pack');
      await store.saveNumberCount(row.line.id, 3);
      await store.addRestock(row, 5);

      final restock = rowOf(
        await store.loadDraft(),
        'Fries pack',
      ).restocks.single;
      final saved = await store.removeRestock(row, restock);

      expect(saved.endQty, 3);
      expect(saved.inQty, 0);
    });

    test('removing stops at 0 if the stock was already used', () async {
      await stock.add(syrup());
      await stock.add(friesPack);
      final draft = await store.loadDraft();
      await store.addRestock(rowOf(draft, 'Caramel syrup'), 4000);
      await store.addRestock(rowOf(draft, 'Fries pack'), 5);

      var after = await store.loadDraft();
      await store.saveContainerCount(
        rowOf(after, 'Caramel syrup'),
        sealed: 1,
        level: levelFull,
        exactQty: null,
      );
      await store.saveNumberCount(rowOf(after, 'Fries pack').line.id, 2);

      await store.removeRestock(
        rowOf(after, 'Caramel syrup'),
        rowOf(after, 'Caramel syrup').restocks.single,
      );
      await store.removeRestock(
        rowOf(after, 'Fries pack'),
        rowOf(after, 'Fries pack').restocks.single,
      );

      after = await store.loadDraft();
      expect(lineOf(after, 'Caramel syrup').sealed, 0);
      expect(lineOf(after, 'Caramel syrup').endQty, 2000);
      expect(lineOf(after, 'Fries pack').endQty, 0);
    });

    test('removing the same restock twice only counts once', () async {
      await stock.add(syrup());
      final row = rowOf(await store.loadDraft(), 'Caramel syrup');
      await store.addRestock(row, 2000);
      await store.addRestock(row, 2000);

      final restock = rowOf(
        await store.loadDraft(),
        'Caramel syrup',
      ).restocks.first;
      await store.removeRestock(row, restock);
      await store.removeRestock(row, restock);

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.sealed, 1);
      expect(line.inQty, 2000);
    });
  });

  group('container finished', () {
    // a syrup line with this count saved, gives back its row
    Future<CountRow> rowWith({
      required int sealed,
      required double level,
      double? exact,
    }) async {
      await stock.add(syrup());
      final draft = await store.loadDraft();
      await store.saveContainerCount(
        draft.rows.single,
        sealed: sealed,
        level: level,
        exactQty: exact,
      );
      return (await store.loadDraft()).rows.single;
    }

    Future<CountLine> currentLine() async {
      return (await store.loadDraft()).rows.single.line;
    }

    test('with sealed left it opens the next one', () async {
      final row = await rowWith(sealed: 2, level: level25);

      await store.finishContainer(row);

      final line = await currentLine();
      expect(line.outCount, 1);
      expect(line.sealed, 1);
      expect(line.level, levelFull);
      expect(line.endQty, 4000);
      expect(line.endIsExact, isFalse);
    });

    test('with no sealed left nothing stays open', () async {
      final row = await rowWith(sealed: 0, level: level25);

      await store.finishContainer(row);

      final line = await currentLine();
      expect(line.outCount, 1);
      expect(line.sealed, 0);
      expect(line.level, levelNone);
      expect(line.endQty, 0);
      expect(line.endIsExact, isTrue);
    });

    test('it clears a typed exact amount', () async {
      final row = await rowWith(sealed: 1, level: levelNone, exact: 350);

      await store.finishContainer(row);

      final line = await currentLine();
      expect(line.exactQty, isNull);
      expect(line.endQty, 2000);
    });

    test('it saves one out event with the values from before', () async {
      final row = await rowWith(sealed: 1, level: levelNone, exact: 350);

      await store.finishContainer(row);

      final event = (await db.query('stock_events')).single;
      expect(event['kind'], 'out');
      expect(event['qty'], 1);
      expect(event['prev_sealed'], 1);
      expect(event['prev_level'], levelNone);
      expect(event['prev_exact'], 350);
    });

    test('it does not change touched', () async {
      await stock.add(syrup());
      // a restock leaves the line untouched and gives it something to finish
      await store.addRestock((await store.loadDraft()).rows.single, 2000);

      await store.finishContainer((await store.loadDraft()).rows.single);

      final line = await currentLine();
      expect(line.outCount, 1);
      expect(line.touched, isFalse);
    });

    test('with nothing open it saves nothing', () async {
      final row = await rowWith(sealed: 0, level: levelNone);

      await store.finishContainer(row);

      expect((await currentLine()).outCount, 0);
      expect(await db.query('stock_events'), isEmpty);
    });

    test('undo with sealed left puts everything back', () async {
      final row = await rowWith(sealed: 2, level: level25);
      await store.finishContainer(row);

      await store.undoFinish(row);

      final line = await currentLine();
      expect(line.outCount, 0);
      expect(line.sealed, 2);
      expect(line.level, level25);
      expect(line.exactQty, isNull);
      expect(line.endQty, 4500);
      expect(await db.query('stock_events'), isEmpty);
    });

    test('undo with no sealed left puts everything back', () async {
      final row = await rowWith(sealed: 0, level: level75);
      await store.finishContainer(row);

      await store.undoFinish(row);

      final line = await currentLine();
      expect(line.sealed, 0);
      expect(line.level, level75);
      expect(line.endQty, 1500);
    });

    test('undo brings a typed exact amount back', () async {
      final row = await rowWith(sealed: 1, level: levelNone, exact: 350);
      await store.finishContainer(row);

      final saved = await store.undoFinish(row);

      expect(saved.exactQty, 350);
      expect(saved.endQty, 2350);
      expect(saved.endIsExact, isTrue);
    });

    test('undo only takes back the last one', () async {
      final row = await rowWith(sealed: 3, level: level50);
      await store.finishContainer(row);
      await store.finishContainer(row);

      await store.undoFinish(row);

      final line = await currentLine();
      expect(line.outCount, 1);
      expect(line.sealed, 2);
      expect(line.level, levelFull);
    });

    test('undo with nothing finished changes nothing', () async {
      final row = await rowWith(sealed: 2, level: level50);

      final saved = await store.undoFinish(row);

      expect(saved.sealed, 2);
      expect(saved.outCount, 0);
    });

    test('undo keeps a restock made after the tap', () async {
      final row = await rowWith(sealed: 1, level: level50);
      await store.finishContainer(row);
      await store.addRestock(row, 2000);

      await store.undoFinish(row);

      final line = await currentLine();
      expect(line.outCount, 0);
      // 1 from before + 1 restock
      expect(line.sealed, 2);
      expect(line.level, level50);
      expect(line.inQty, 2000);
      expect(line.endQty, 5000);
    });

    test('undo keeps a sealed count edited after the tap', () async {
      final row = await rowWith(sealed: 2, level: level50);
      await store.finishContainer(row);
      await store.saveContainerCount(
        row,
        sealed: 5,
        level: levelFull,
        exactQty: null,
      );

      await store.undoFinish(row);

      final line = await currentLine();
      expect(line.sealed, 6);
      expect(line.level, level50);
    });

    test('undo keeps a level changed after the tap', () async {
      final row = await rowWith(sealed: 1, level: level50);
      await store.finishContainer(row);
      await store.saveContainerCount(
        row,
        sealed: 0,
        level: level25,
        exactQty: null,
      );

      await store.undoFinish(row);

      final line = await currentLine();
      expect(line.outCount, 0);
      expect(line.sealed, 1);
      expect(line.level, level25);
    });

    test('undo keeps an exact amount typed after the tap', () async {
      final row = await rowWith(sealed: 1, level: level50);
      await store.finishContainer(row);
      await store.saveContainerCount(
        row,
        sealed: 0,
        level: levelFull,
        exactQty: 300,
      );

      await store.undoFinish(row);

      final line = await currentLine();
      expect(line.sealed, 1);
      expect(line.exactQty, 300);
      expect(line.endQty, 2300);
    });

    test('undo of a tap with no sealed adds no sealed', () async {
      final row = await rowWith(sealed: 0, level: level50);
      await store.finishContainer(row);
      await store.addRestock(row, 2000);

      await store.undoFinish(row);

      final line = await currentLine();
      // only the restock, that tap took nothing out of sealed
      expect(line.sealed, 1);
      expect(line.level, level50);
    });
  });

  group('when the owner changes an item during the day', () {
    test('a new container size works End out again, Start stays', () async {
      final id = await stock.add(syrup());
      final day = await addDay('2026-10-31');
      await addLine(day, id, end: 4000, sealed: 2, level: levelNone);
      await store.loadDraft();

      final item = (await stock.list()).single;
      await stock.update(item.copyWith(containerSize: 1000));

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.startQty, 4000);
      expect(line.endQty, 2000);
    });

    test('a changed count type starts the draft line over', () async {
      await stock.add(syrup());
      await store.loadDraft();

      final item = (await stock.list()).single;
      await stock.update(
        item.copyWith(
          countType: CountType.number,
          baseUnit: BaseUnit.pcs,
          lowMode: LowMode.exact,
        ),
      );

      final line = lineOf(await store.loadDraft(), 'Caramel syrup');
      expect(line.sealed, isNull);
      expect(line.level, isNull);
      expect(line.endQty, 0);
    });
  });

  group('used today', () {
    late int stockId;
    late int latteId;
    late int dayId;
    late MenuItemStore menu;
    late RecipeStore recipes;

    setUp(() async {
      menu = MenuItemStore(db, clock: () => now);
      recipes = RecipeStore(db, clock: () => now);
      stockId = await stock.add(syrup());
      await stock.add(friesPack);
      latteId = await menu.add(
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      await recipes.addLine(latteId, stockId, 30);
      dayId = (await store.loadDraft()).day.id;
    });

    Future<CountRow> syrupRow() async {
      final draft = await store.loadDraft();
      return draft.rows.firstWhere((row) => row.item.id == stockId);
    }

    test('nothing tallied = not used', () async {
      expect((await syrupRow()).usedToday, isFalse);
    });

    test('a tallied menu item uses its recipe items only', () async {
      await store.tally.add(dayId, latteId);

      final draft = await store.loadDraft();
      final used = draft.rows.where((row) => row.usedToday);
      expect(used.map((row) => row.item.name), ['Caramel syrup']);
    });

    test('a tally taken back to 0 is not used', () async {
      await store.tally.add(dayId, latteId);
      await store.tally.remove(dayId, latteId);

      expect((await syrupRow()).usedToday, isFalse);
    });

    test('2 menu items with the same item give one row', () async {
      final mochaId = await menu.add(
        const MenuItem(name: 'Mocha', category: 'Coffee'),
      );
      await recipes.addLine(mochaId, stockId, 10);
      await store.tally.add(dayId, latteId);
      await store.tally.add(dayId, mochaId);

      final draft = await store.loadDraft();
      expect(draft.rows.where((row) => row.usedToday), hasLength(1));
    });

    test('a removed recipe line doesnt count', () async {
      final lines = await recipes.lines(latteId);
      await recipes.removeLine(lines.single.id);
      await store.tally.add(dayId, latteId);

      expect((await syrupRow()).usedToday, isFalse);
    });

    test('a tally from another day doesnt count', () async {
      final oldDay = await db.insert('business_days', {
        'business_date': '2020-01-01',
        'status': 'closed',
      });
      await store.tally.add(oldDay, latteId);

      expect((await syrupRow()).usedToday, isFalse);
    });

    test('the badge leaves once the count is touched, used stays', () async {
      await store.tally.add(dayId, latteId);
      var row = await syrupRow();
      expect(row.needsDoubleCheck, isTrue);

      await store.saveContainerCount(
        row,
        sealed: 1,
        level: levelNone,
        exactQty: null,
      );

      row = await syrupRow();
      expect(row.needsDoubleCheck, isFalse);
      expect(row.usedToday, isTrue);
    });
  });
}
