import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/history_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/units.dart';

import '../helpers/test_database.dart';

StockItem pieces(String name, {String category = 'Food'}) {
  return StockItem(
    name: name,
    category: category,
    baseUnit: BaseUnit.pcs,
    countType: CountType.number,
    lowMode: LowMode.exact,
    lowValue: 0,
  );
}

void main() {
  late Database db;
  late CountStore counts;
  late HistoryStore history;
  late StockItemStore stock;
  late DateTime now;

  setUp(() async {
    db = await openTestDatabase();
    now = DateTime.utc(2026, 11, 1, 10);
    counts = CountStore(db, clock: () => now);
    history = counts.history;
    stock = StockItemStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // submits the draft on its own date and gives back its id
  Future<int> submitDraft({String? date, bool open = true}) async {
    final draft = await counts.loadDraft();
    await counts.submits.submit(
      draft.day.id,
      date: date ?? draft.day.businessDate,
      skippedDaysOpen: open,
    );
    return draft.day.id;
  }

  group('days', () {
    test('no days before the first submit, the draft is not history', () async {
      await counts.loadDraft();

      expect(await history.days(), isEmpty);
    });

    test('submitted and closed days, newest first', () async {
      await submitDraft();
      await submitDraft(date: '2026-11-04', open: false);

      final days = await history.days();

      expect(days.map((day) => day.businessDate), [
        '2026-11-04',
        '2026-11-03',
        '2026-11-02',
        '2026-11-01',
      ]);
      expect(days.map((day) => day.status), [
        'submitted',
        'closed',
        'closed',
        'submitted',
      ]);
    });

    test('a count covering open days knows its first date', () async {
      await submitDraft(date: '2026-11-03');

      final day = (await history.days()).single;

      expect(day.coversFrom, '2026-11-01');
      expect(day.submittedAt, '2026-11-01T10:00:00.000Z');
    });
  });

  group('detail', () {
    test('count rows by category then name, with notes', () async {
      await stock.add(pieces('Wings'));
      await stock.add(pieces('Cups', category: 'Packaging'));
      final friesId = await stock.add(pieces('Fries pack'));
      final draft = await counts.loadDraft();
      final fries = draft.rows.firstWhere((row) => row.item.id == friesId);
      await counts.saveNumberCount(fries.line.id, 8);
      await counts.saveNote(fries.line.id, '2 packs expired');
      final dayId = await submitDraft();

      final detail = await history.detail(dayId);

      expect(detail.rows.map((row) => row.item.name), [
        'Fries pack',
        'Wings',
        'Cups',
      ]);
      expect(detail.rows.first.line.endQty, 8);
      expect(detail.rows.first.line.note, '2 packs expired');
    });

    test('an item archived later still shows on its past days', () async {
      final id = await stock.add(pieces('Wings'));
      final dayId = await submitDraft();
      await stock.archive(id);

      final detail = await history.detail(dayId);

      expect(detail.rows.single.item.name, 'Wings');
    });

    test('an item archived during the day stays hidden', () async {
      await stock.add(pieces('Wings'));
      final oldId = await stock.add(pieces('Old lids'));
      await counts.loadDraft();
      await stock.archive(oldId);
      final dayId = await submitDraft();

      final detail = await history.detail(dayId);

      expect(detail.rows.map((row) => row.item.name), ['Wings']);
    });

    test('the tally has the items made, archived ones too', () async {
      final menu = MenuItemStore(db, clock: () => now);
      final latte = await menu.add(
        const MenuItem(name: 'Latte', category: 'Coffee'),
      );
      final soup = await menu.add(
        const MenuItem(name: 'Soup', category: 'Food'),
      );
      await menu.add(const MenuItem(name: 'Mocha', category: 'Coffee'));
      final dayId = (await counts.loadDraft()).day.id;
      await counts.tally.add(dayId, soup);
      await counts.tally.add(dayId, latte);
      await counts.tally.add(dayId, latte);
      await submitDraft();
      await menu.archive(soup);

      final detail = await history.detail(dayId);

      expect(detail.tally.map((row) => row.item.name), ['Latte', 'Soup']);
      expect(detail.tally.first.qty, 2);
    });

    test('a closed day has no rows and no tally', () async {
      await stock.add(pieces('Wings'));
      await submitDraft(date: '2026-11-02', open: false);
      final closed = (await history.days()).firstWhere(
        (day) => day.status == 'closed',
      );

      final detail = await history.detail(closed.id);

      expect(detail.rows, isEmpty);
      expect(detail.tally, isEmpty);
    });
  });
}
