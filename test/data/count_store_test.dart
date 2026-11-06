import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_line.dart';
import 'package:brewmanager/data/count_store.dart';
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
}
