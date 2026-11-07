import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/tally_store.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late TallyStore store;
  late MenuItemStore menu;
  late int dayId;

  Future<int> addItem(String name, {String category = 'Coffee'}) {
    return menu.add(MenuItem(name: name, category: category));
  }

  // what the day's tally looks like: name -> quantity, only lines above 0
  Future<Map<String, int>> tallied() async {
    final rows = await store.load(dayId);
    return {
      for (final row in rows)
        if (row.qty > 0) row.item.name: row.qty,
    };
  }

  setUp(() async {
    db = await openTestDatabase();
    store = TallyStore(db);
    menu = MenuItemStore(db);
    final draft = await CountStore(db).loadDraft();
    dayId = draft.day.id;
  });

  tearDown(() async {
    await db.close();
  });

  test('load gives every active item at 0, by category then name', () async {
    await addItem('Latte');
    await addItem('Americano');
    await addItem('Fries', category: 'Food');

    final rows = await store.load(dayId);

    expect(rows.map((row) => row.item.name), ['Americano', 'Latte', 'Fries']);
    expect(rows.every((row) => row.qty == 0), isTrue);
  });

  test('add counts up on one line', () async {
    final id = await addItem('Latte');

    await store.add(dayId, id);
    await store.add(dayId, id);

    expect(await tallied(), {'Latte': 2});
    expect(await db.query('tally_lines'), hasLength(1));
  });

  test('taps that dont wait for each other all count', () async {
    final id = await addItem('Latte');

    await Future.wait([
      store.add(dayId, id),
      store.add(dayId, id),
      store.add(dayId, id),
    ]);

    expect(await tallied(), {'Latte': 3});
  });

  test('remove counts down, the line goes at 0', () async {
    final id = await addItem('Latte');
    await store.add(dayId, id);
    await store.add(dayId, id);

    await store.remove(dayId, id);
    expect(await tallied(), {'Latte': 1});

    await store.remove(dayId, id);
    expect(await tallied(), isEmpty);
    expect(await db.query('tally_lines'), isEmpty);
  });

  test('remove with nothing tallied does nothing', () async {
    final id = await addItem('Latte');

    await store.remove(dayId, id);

    expect(await db.query('tally_lines'), isEmpty);
  });

  test('only menu item and quantity get saved', () async {
    final id = await menu.add(
      const MenuItem(name: 'Latte', category: 'Coffee', priceHint: 120),
    );

    await store.add(dayId, id);

    final line = (await db.query('tally_lines')).single;
    expect(line.keys.toSet(), {'id', 'day_id', 'menu_item_id', 'qty'});
  });

  test('an archived item stays only if it was tallied that day', () async {
    final kept = await addItem('Latte');
    final gone = await addItem('Mocha');
    await store.add(dayId, kept);
    await menu.archive(kept);
    await menu.archive(gone);

    final rows = await store.load(dayId);

    expect(rows.map((row) => row.item.name), ['Latte']);
    expect(rows.single.qty, 1);
    expect(rows.single.item.isArchived, isTrue);
  });
}
