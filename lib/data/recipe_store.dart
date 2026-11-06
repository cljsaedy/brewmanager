import 'package:sqflite/sqflite.dart';

import '../logic/formatting.dart';
import '../logic/units.dart';
import 'menu_item_store.dart';

// one active recipe line, with the stock item's name and unit so the screen can show it
// like "Whole milk · 150 ml"
class RecipeLine {
  const RecipeLine({
    required this.id,
    required this.menuItemId,
    required this.stockItemId,
    required this.stockName,
    required this.baseUnit,
    required this.amount,
    this.inputUnit,
  });

  final int id;
  final int menuItemId;
  final int stockItemId;
  final String stockName;
  final BaseUnit baseUnit;
  // in the stock item's base unit, like 150 (ml)
  final double amount;
  // the unit the owner typed, like 'oz', null = typed in the base unit
  // only for showing, the math always uses amount
  final String? inputUnit;

  // the unit to show the amount in, the base unit when none was saved
  InputUnit get shownUnit {
    final units = inputUnitsFor(baseUnit);
    return units.firstWhere(
      (unit) => unit.label == inputUnit,
      orElse: () => units.first,
    );
  }

  // the amount back in the typed unit, like 177.441 ml -> 6 (oz)
  double get shownAmount => roundAmount(amount / shownUnit.factor);

  // what the screen shows: "6 oz (177.44 ml)", or just "150 ml" when typed in the base unit
  String get amountText {
    final base = formatWithUnit(amount, baseUnit.name);
    final unit = shownUnit;
    if (unit.factor == 1) return base;
    return '${formatWithUnit(shownAmount, unit.label)} ($base)';
  }
}

// the recipe of each menu item = how much of each stock item it uses (rule 6)
// lines are never deleted or changed in place, old ones get archived so old days can be recalculated (rule 12)
class RecipeStore {
  RecipeStore(this._db, {Clock clock = utcNow}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  // the active lines of one menu item, a-z by stock item name
  Future<List<RecipeLine>> lines(int menuItemId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT r.id, r.menu_item_id, r.stock_item_id, r.amount, r.input_unit,
             s.name AS stock_name, s.base_unit
      FROM recipe_lines r
      JOIN stock_items s ON s.id = r.stock_item_id
      WHERE r.menu_item_id = ? AND r.is_archived = 0
      ORDER BY s.name COLLATE NOCASE
      ''',
      [menuItemId],
    );
    return rows
        .map(
          (row) => RecipeLine(
            id: row['id'] as int,
            menuItemId: row['menu_item_id'] as int,
            stockItemId: row['stock_item_id'] as int,
            stockName: row['stock_name'] as String,
            baseUnit: BaseUnit.values.byName(row['base_unit'] as String),
            amount: (row['amount'] as num).toDouble(),
            inputUnit: row['input_unit'] as String?,
          ),
        )
        .toList();
  }

  // adds a stock item to a menu item's recipe, amount already in the stock item's base unit
  // inputUnit = the unit the owner typed, null when it was the base unit
  // gives back the new line id
  Future<int> addLine(
    int menuItemId,
    int stockItemId,
    double amount, {
    String? inputUnit,
  }) async {
    _checkAmount(amount);

    final menuRows = await _db.query(
      'menu_items',
      columns: ['no_stock', 'is_archived'],
      where: 'id = ?',
      whereArgs: [menuItemId],
    );
    if (menuRows.isEmpty) throw StateError('No menu item with id $menuItemId');
    final menu = menuRows.first;
    if (menu['is_archived'] == 1) {
      throw MenuItemException(
        'Restore this menu item before changing its recipe.',
      );
    }
    if (menu['no_stock'] == 1) {
      throw MenuItemException(
        'Untick "Not compared (no recipe needed)" before adding to the recipe.',
      );
    }

    final stockRows = await _db.query(
      'stock_items',
      columns: ['name', 'is_archived'],
      where: 'id = ?',
      whereArgs: [stockItemId],
    );
    if (stockRows.isEmpty) {
      throw StateError('No stock item with id $stockItemId');
    }
    final stockName = stockRows.first['name'] as String;
    // recipes never show archived stock items (rule 12)
    if (stockRows.first['is_archived'] == 1) {
      throw MenuItemException('$stockName is archived. Restore it first.');
    }

    // one stock item at most once per menu item (rule 6), the db would refuse it too
    final taken = await _db.query(
      'recipe_lines',
      where: 'menu_item_id = ? AND stock_item_id = ? AND is_archived = 0',
      whereArgs: [menuItemId, stockItemId],
    );
    if (taken.isNotEmpty) {
      throw MenuItemException(
        '$stockName is already in this recipe. Change its amount instead.',
      );
    }

    return _db.insert('recipe_lines', {
      'menu_item_id': menuItemId,
      'stock_item_id': stockItemId,
      'amount': amount,
      'input_unit': inputUnit,
      'created_at': _clock().toIso8601String(),
    });
  }

  // changes a line's amount the rule 12 way: archive the old line, add a new one
  // both use the same time, so for any moment exactly one of them was active:
  // a day submitted before that time used the old amount, after it the new one
  // gives back the id of the line that is active now
  Future<int> changeAmount(
    int lineId,
    double amount, {
    String? inputUnit,
  }) async {
    _checkAmount(amount);
    final now = _clock().toIso8601String();

    // transaction = archive + insert happen together or not at all
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'recipe_lines',
        where: 'id = ? AND is_archived = 0',
        whereArgs: [lineId],
      );
      if (rows.isEmpty) {
        throw StateError('No active recipe line with id $lineId');
      }
      final old = rows.first;

      // same amount and unit = nothing to change, dont make a new line for it
      // 1000 ml changed to 1 L is the same amount but a new unit to show, so that one goes through
      if ((old['amount'] as num).toDouble() == amount &&
          old['input_unit'] == inputUnit) {
        return lineId;
      }

      await txn.update(
        'recipe_lines',
        {'is_archived': 1, 'archived_at': now},
        where: 'id = ?',
        whereArgs: [lineId],
      );
      return txn.insert('recipe_lines', {
        'menu_item_id': old['menu_item_id'],
        'stock_item_id': old['stock_item_id'],
        'amount': amount,
        'input_unit': inputUnit,
        'created_at': now,
      });
    });
  }

  // takes a stock item out of the recipe, the line is archived not deleted (rule 12)
  Future<void> removeLine(int lineId) async {
    await _db.update(
      'recipe_lines',
      {'is_archived': 1, 'archived_at': _clock().toIso8601String()},
      where: 'id = ? AND is_archived = 0',
      whereArgs: [lineId],
    );
  }

  // the recipe amount has to be more than 0 (the db checks this too)
  void _checkAmount(double amount) {
    if (amount <= 0) throw MenuItemException('Amount must be more than 0.');
  }
}
