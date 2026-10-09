import 'package:sqflite/sqflite.dart';

import '../models/recipe_blueprint.dart';
import 'database_helper.dart';

/// thrown when the ingredient is already in the recipe (UNIQUE on menu_item_id + ingredient_id)
class DuplicateIngredientException implements Exception {}

/// all db access for the recipe_blueprints table
class RecipeRepository {
  RecipeRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// recipe lines for one menu item, joined with ingredients for name and unit
  Future<List<RecipeBlueprint>> getForMenuItem(int menuItemId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT rb.blueprint_id, rb.menu_item_id, rb.ingredient_id,
             rb.quantity_required,
             i.name AS ingredient_name, i.unit_of_measure
      FROM recipe_blueprints rb
      JOIN ingredients i ON i.ingredient_id = rb.ingredient_id
      WHERE rb.menu_item_id = ?
      ORDER BY i.name COLLATE NOCASE
    ''', [menuItemId]);
    return rows.map(RecipeBlueprint.fromMap).toList();
  }

  /// every recipe line grouped by menu item, one query instead of one per item on the pos grid
  Future<Map<int, List<RecipeBlueprint>>> getAllGroupedByMenuItem() async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT rb.blueprint_id, rb.menu_item_id, rb.ingredient_id,
             rb.quantity_required,
             i.name AS ingredient_name, i.unit_of_measure
      FROM recipe_blueprints rb
      JOIN ingredients i ON i.ingredient_id = rb.ingredient_id
    ''');

    final grouped = <int, List<RecipeBlueprint>>{};
    for (final row in rows) {
      final line = RecipeBlueprint.fromMap(row);
      grouped.putIfAbsent(line.menuItemId, () => []).add(line);
    }
    return grouped;
  }

  /// returns the new blueprint_id
  Future<int> add(int menuItemId, int ingredientId, double quantity) async {
    final db = await _helper.database;
    try {
      return await db.insert('recipe_blueprints', {
        'menu_item_id': menuItemId,
        'ingredient_id': ingredientId,
        'quantity_required': quantity,
      });
    } on DatabaseException catch (e) {
      // the UNIQUE constraint is the backstop if the same ingredient gets added twice, otherwise it would deduct twice on every sale
      if (e.isUniqueConstraintError()) throw DuplicateIngredientException();
      rethrow;
    }
  }

  Future<void> updateQuantity(int blueprintId, double quantity) async {
    final db = await _helper.database;
    await db.update(
      'recipe_blueprints',
      {'quantity_required': quantity},
      where: 'blueprint_id = ?',
      whereArgs: [blueprintId],
    );
  }

  /// a real delete, not archive, since nothing historical points at a blueprint row
  /// (past sales already wrote their deductions to batch_deductions, changing the recipe only affects future sales)
  Future<void> remove(int blueprintId) async {
    final db = await _helper.database;
    await db.delete(
      'recipe_blueprints',
      where: 'blueprint_id = ?',
      whereArgs: [blueprintId],
    );
  }
}
