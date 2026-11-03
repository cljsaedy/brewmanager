import 'package:sqflite/sqflite.dart';

import 'menu_item.dart';

// thrown when a menu item or recipe breaks a rule, message is plain words the screen can show
class MenuItemException implements Exception {
  MenuItemException(this.message);

  final String message;

  @override
  String toString() => message;
}

// thrown when the name is already used by another menu item (names ignore case and end spaces)
// existing.isArchived = true means the screen should offer to restore that item instead (rule 12)
class MenuNameTakenException implements Exception {
  MenuNameTakenException(this.existing);

  final MenuItem existing;

  @override
  String toString() => 'The name "${existing.name}" is already used.';
}

// a function that gives the current time, the stores save it as utc iso text like 2026-11-01T05:30:00.000Z
// the app uses utcNow, tests pass their own clock so the saved times are known
typedef Clock = DateTime Function();
DateTime utcNow() => DateTime.now().toUtc();

// add, edit, list, archive and restore menu items
// items are never deleted, only archived, so old tallies and reports still find them (rule 12)
class MenuItemStore {
  MenuItemStore(this._db, {Clock clock = utcNow}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  // active items (or archived ones), ordered by category then name, ignoring case
  Future<List<MenuItem>> list({bool archived = false}) async {
    final rows = await _db.query(
      'menu_items',
      where: 'is_archived = ?',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(MenuItem.fromRow).toList();
  }

  // categories already used by active items, for the suggestions in the form
  // GROUP BY ... COLLATE NOCASE = "Coffee" and "coffee" come back once, like the list groups them
  Future<List<String>> categories() async {
    final rows = await _db.rawQuery(
      'SELECT category FROM menu_items WHERE is_archived = 0 '
      'GROUP BY category COLLATE NOCASE '
      'ORDER BY category COLLATE NOCASE',
    );
    return rows.map((row) => row['category'] as String).toList();
  }

  // finds an item by name, archived ones too, ignoring case and end spaces
  // the name column is COLLATE NOCASE so "= ?" already ignores case
  Future<MenuItem?> findByName(String name) async {
    final rows = await _db.query(
      'menu_items',
      where: 'name = ?',
      whereArgs: [name.trim()],
    );
    if (rows.isEmpty) return null;
    return MenuItem.fromRow(rows.first);
  }

  // saves a new item, gives back its new id
  // a new item has no recipe yet, so no_stock can be on right away
  Future<int> add(MenuItem item) async {
    _checkRules(item);
    final existing = await findByName(item.name);
    if (existing != null) throw MenuNameTakenException(existing);

    return _db.insert('menu_items', item.toRow());
  }

  // saves changes to an item that already exists
  Future<void> update(MenuItem item) async {
    final id = item.id;
    if (id == null) throw ArgumentError('Item has no id, use add() instead');
    _checkRules(item);

    // the name can stay the same, but it cant take another item's name
    final existing = await findByName(item.name);
    if (existing != null && existing.id != id) {
      throw MenuNameTakenException(existing);
    }

    // "doesn't use tracked stock" only when the recipe is empty, so no lines get removed silently (rule 6)
    if (item.noStock && await activeLineCount(id) > 0) {
      throw MenuItemException(
        "Remove the recipe lines first, then tick \"Doesn't use tracked "
        'stock".',
      );
    }

    await _db.update(
      'menu_items',
      item.toRow(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // how many active recipe lines the item has
  Future<int> activeLineCount(int id) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM recipe_lines '
      'WHERE menu_item_id = ? AND is_archived = 0',
      [id],
    );
    return rows.first['n'] as int;
  }

  // active recipe line count of every menu item that has at least one, as {menu item id: count}
  // one query for the whole table, items missing from the map have no recipe yet
  Future<Map<int, int>> lineCounts() async {
    final rows = await _db.rawQuery(
      'SELECT menu_item_id, COUNT(*) AS n FROM recipe_lines '
      'WHERE is_archived = 0 GROUP BY menu_item_id',
    );
    return {
      for (final row in rows) row['menu_item_id'] as int: row['n'] as int,
    };
  }

  // hides the item from the tally and setup lists, it stays in the db for old reports
  // its active recipe lines get archived too, with the exact same time as the item (rule 12),
  // that time is how restore finds them again
  // transaction = both changes happen together or not at all
  Future<void> archive(int id) async {
    final now = _clock().toIso8601String();
    await _db.transaction((txn) async {
      await txn.update(
        'menu_items',
        {'is_archived': 1, 'archived_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'recipe_lines',
        {'is_archived': 1, 'archived_at': now},
        where: 'menu_item_id = ? AND is_archived = 0',
        whereArgs: [id],
      );
    });
  }

  // brings an archived item back with its old recipe
  // the lines archived with it are copied as new active lines (new created_at),
  // the old ones stay archived so the history of old days is not changed (rule 12)
  // lines for stock items that got archived in the meantime are left out, since recipes
  // never show archived stock items, their names are given back so the screen can say so
  Future<List<String>> restore(int id) async {
    final now = _clock().toIso8601String();
    final leftOut = <String>[];

    await _db.transaction((txn) async {
      final itemRows = await txn.query(
        'menu_items',
        columns: ['archived_at'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (itemRows.isEmpty) throw StateError('No menu item with id $id');
      final archivedAt = itemRows.first['archived_at'] as String?;
      // already active, nothing to do
      if (archivedAt == null) return;

      // the lines archived together with the item, and if their stock item is still active
      final lines = await txn.rawQuery(
        '''
        SELECT r.stock_item_id, r.amount, s.name AS stock_name, s.is_archived AS stock_archived
        FROM recipe_lines r
        JOIN stock_items s ON s.id = r.stock_item_id
        WHERE r.menu_item_id = ? AND r.archived_at = ?
        ORDER BY s.name COLLATE NOCASE
        ''',
        [id, archivedAt],
      );

      for (final line in lines) {
        if (line['stock_archived'] == 1) {
          leftOut.add(line['stock_name'] as String);
          continue;
        }
        await txn.insert('recipe_lines', {
          'menu_item_id': id,
          'stock_item_id': line['stock_item_id'],
          'amount': line['amount'],
          'created_at': now,
        });
      }

      await txn.update(
        'menu_items',
        {'is_archived': 0, 'archived_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    return leftOut;
  }

  // throws with the plain words message if a rule is broken
  void _checkRules(MenuItem item) {
    final problem = menuItemProblem(item);
    if (problem != null) throw MenuItemException(problem);
  }
}
