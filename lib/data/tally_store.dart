import 'package:sqflite/sqflite.dart';

import 'menu_item.dart';

// one menu item with how many were made on the day
class TallyRow {
  const TallyRow({required this.item, required this.qty});

  final MenuItem item;
  final int qty;
}

// the tally of a day, only menu item + quantity gets saved, never prices or totals
class TallyStore {
  TallyStore(this._db);

  final Database _db;

  // every active menu item, ordered by category then name, with its quantity on this day
  // an archived item comes too if it was tallied this day, so its number doesnt get lost
  // LEFT JOIN = items with no tally line yet still come back, COALESCE turns their empty qty into 0
  Future<List<TallyRow>> load(int dayId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT menu_items.*, COALESCE(tally_lines.qty, 0) AS qty
      FROM menu_items
      LEFT JOIN tally_lines
        ON tally_lines.menu_item_id = menu_items.id
        AND tally_lines.day_id = ?
      WHERE menu_items.is_archived = 0 OR tally_lines.qty > 0
      ORDER BY menu_items.category COLLATE NOCASE,
               menu_items.name COLLATE NOCASE
      ''',
      [dayId],
    );
    return rows
        .map(
          (row) =>
              TallyRow(item: MenuItem.fromRow(row), qty: row['qty'] as int),
        )
        .toList();
  }

  // adds 1 to a menu item, autosaved on every tap
  // the db adds to the number it has, so fast taps cant overwrite each other
  // INSERT OR IGNORE = makes the line at 0 only if it isnt there yet
  // transaction = both steps happen together or not at all
  Future<void> add(int dayId, int menuItemId) async {
    await _db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR IGNORE INTO tally_lines (day_id, menu_item_id, qty) '
        'VALUES (?, ?, 0)',
        [dayId, menuItemId],
      );
      await txn.rawUpdate(
        'UPDATE tally_lines SET qty = qty + 1 '
        'WHERE day_id = ? AND menu_item_id = ?',
        [dayId, menuItemId],
      );
    });
  }

  // takes 1 off a menu item, it stops at 0 and a line at 0 gets removed
  Future<void> remove(int dayId, int menuItemId) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE tally_lines SET qty = qty - 1 '
        'WHERE day_id = ? AND menu_item_id = ? AND qty > 0',
        [dayId, menuItemId],
      );
      await txn.delete(
        'tally_lines',
        where: 'day_id = ? AND menu_item_id = ? AND qty = 0',
        whereArgs: [dayId, menuItemId],
      );
    });
  }
}
