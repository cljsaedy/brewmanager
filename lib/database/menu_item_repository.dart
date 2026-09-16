import 'package:sqflite/sqflite.dart';

import '../models/menu_item.dart';
import 'database_helper.dart';
import 'ingredient_repository.dart' show DuplicateNameException;

/// all db access for the menu_items table
class MenuItemRepository {
  MenuItemRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// active items sorted by name
  Future<List<MenuItem>> getActive() async {
    final db = await _helper.database;
    final rows = await db.query(
      'menu_items',
      where: 'is_archived = 0',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(MenuItem.fromMap).toList();
  }

  /// returns the new menu_item_id
  Future<int> insert(String name, double sellingPrice) async {
    final db = await _helper.database;
    try {
      return await db.insert('menu_items', {
        'name': name.trim(),
        'selling_price': sellingPrice,
        'is_archived': 0,
      });
    } on DatabaseException catch (e) {
      // name is UNIQUE, give the screen something it can show
      if (e.isUniqueConstraintError()) throw DuplicateNameException(name);
      rethrow;
    }
  }

  Future<void> update(MenuItem item) async {
    final db = await _helper.database;
    try {
      await db.update(
        'menu_items',
        item.toMap(),
        where: 'menu_item_id = ?',
        whereArgs: [item.menuItemId],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw DuplicateNameException(item.name);
      rethrow;
    }
  }

  /// marks as archived, no delete since past sales reference menu items
  Future<void> archive(int menuItemId) async {
    final db = await _helper.database;
    await db.update(
      'menu_items',
      {'is_archived': 1},
      where: 'menu_item_id = ?',
      whereArgs: [menuItemId],
    );
  }
}
