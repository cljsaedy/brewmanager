import 'package:sqflite/sqflite.dart';

import 'stock_item.dart';

// thrown when a stock item breaks a rule, message is plain words the screen can show
class StockItemException implements Exception {
  StockItemException(this.message);

  final String message;

  @override
  String toString() => message;
}

// thrown when the name is already used by another item (names ignore case and end spaces)
// existing.isArchived = true means the screen should offer to restore that item instead (rule 12)
class NameTakenException implements Exception {
  NameTakenException(this.existing);

  final StockItem existing;

  @override
  String toString() => 'The name "${existing.name}" is already used.';
}

// add, edit, list, archive and restore stock items
// items are never deleted, only archived, so old counts and reports still find them (rule 12)
class StockItemStore {
  StockItemStore(this._db);

  final Database _db;

  // active items (or archived ones), ordered by category then name, ignoring case
  Future<List<StockItem>> list({bool archived = false}) async {
    final rows = await _db.query(
      'stock_items',
      where: 'is_archived = ?',
      whereArgs: [archived ? 1 : 0],
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    return rows.map(StockItem.fromRow).toList();
  }

  // categories already used by active items, for the suggestions in the form
  Future<List<String>> categories() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT category FROM stock_items WHERE is_archived = 0 '
      'ORDER BY category COLLATE NOCASE',
    );
    return rows.map((row) => row['category'] as String).toList();
  }

  // finds an item by name, archived ones too, ignoring case and end spaces
  // the name column is COLLATE NOCASE so "= ?" already ignores case
  Future<StockItem?> findByName(String name) async {
    final rows = await _db.query(
      'stock_items',
      where: 'name = ?',
      whereArgs: [name.trim()],
    );
    if (rows.isEmpty) return null;
    return StockItem.fromRow(rows.first);
  }

  // saves a new item, gives back its new id
  Future<int> add(StockItem item) async {
    _checkRules(item);
    final existing = await findByName(item.name);
    if (existing != null) throw NameTakenException(existing);

    return _db.insert('stock_items', item.toRow());
  }

  // saves changes to an item that already exists
  Future<void> update(StockItem item) async {
    final id = item.id;
    if (id == null) throw ArgumentError('Item has no id, use add() instead');
    _checkRules(item);

    // the name can stay the same, but it cant take another item's name
    final existing = await findByName(item.name);
    if (existing != null && existing.id != id) {
      throw NameTakenException(existing);
    }

    // once used, the base unit and count type are locked
    // changing ml -> g would make the old counts and recipe amounts mean the wrong thing
    // container size can still change (new bottle size), old ends are already saved in base units
    final old = await _get(id);
    if (await isUsed(id) &&
        (old.baseUnit != item.baseUnit || old.countType != item.countType)) {
      throw StockItemException(
        'This item is already in past counts or recipes, so its unit and '
        'count type cannot change. Archive it and add a new item instead.',
      );
    }

    await _db.update(
      'stock_items',
      item.toRow(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // true when the item is in a submitted count or in any recipe (archived recipe lines too)
  // draft count lines dont count, since nothing is final until submit
  Future<bool> isUsed(int id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT
        EXISTS (
          SELECT 1 FROM count_lines c
          JOIN business_days d ON d.id = c.day_id
          WHERE c.stock_item_id = ? AND d.status <> 'draft'
        )
        OR EXISTS (SELECT 1 FROM recipe_lines WHERE stock_item_id = ?)
        AS used
      ''',
      [id, id],
    );
    return rows.first['used'] == 1;
  }

  // gives back why the item cant be archived, or null if it can (rule 12)
  // blocked while any active recipe line uses it, so recipes never point to a hidden item
  // archived recipe lines dont block it, they are only kept for old reports
  Future<String?> archiveProblem(int id) async {
    final item = await _get(id);
    // the menu item + size of every active recipe line that uses this stock item
    final rows = await _db.rawQuery(
      '''
      SELECT m.name AS menu_name, s.label AS size_label
      FROM recipe_lines r
      JOIN menu_sizes s ON s.id = r.menu_size_id
      JOIN menu_items m ON m.id = s.menu_item_id
      WHERE r.stock_item_id = ? AND r.is_archived = 0
      ORDER BY m.name COLLATE NOCASE, s.sort_order, s.label COLLATE NOCASE
      ''',
      [id],
    );
    if (rows.isEmpty) return null;

    // group the sizes under their menu item, like {'Caramel latte': ['Small', 'Large']}
    // a map keeps the order the keys were added, so the sql order stays
    final sizesByMenu = <String, List<String>>{};
    for (final row in rows) {
      final menu = row['menu_name'] as String;
      sizesByMenu.putIfAbsent(menu, () => []).add(row['size_label'] as String);
    }
    // like "Caramel latte (Small, Large), Iced caramel (Regular)"
    final usedIn = sizesByMenu.entries
        .map((e) => '${e.key} (${e.value.join(', ')})')
        .join(', ');

    return "Can't archive ${item.name}. It's used in: $usedIn. "
        'Remove or replace it in those recipes first.';
  }

  // hides the item from the count and setup lists, it stays in the db for old reports
  // checks archiveProblem first so no screen can skip the recipe rule
  Future<void> archive(int id) async {
    final problem = await archiveProblem(id);
    if (problem != null) throw StockItemException(problem);
    await _setArchived(id, true);
  }

  // brings an archived item back, with all its old settings
  Future<void> restore(int id) => _setArchived(id, false);

  Future<void> _setArchived(int id, bool archived) async {
    await _db.update(
      'stock_items',
      {'is_archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // gets one item by id
  Future<StockItem> _get(int id) async {
    final rows = await _db.query(
      'stock_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('No stock item with id $id');
    return StockItem.fromRow(rows.first);
  }

  // throws with the plain words message if a rule is broken
  void _checkRules(StockItem item) {
    final problem = stockItemProblem(item);
    if (problem != null) throw StockItemException(problem);
  }
}
