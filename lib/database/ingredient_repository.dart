import 'package:sqflite/sqflite.dart';

import '../models/ingredient.dart';
import 'database_helper.dart';

/// thrown when a name is already taken, screens show this instead of a raw sql error
class DuplicateNameException implements Exception {
  DuplicateNameException(this.name);
  final String name;
}

/// all db access for the ingredients table
class IngredientRepository {
  IngredientRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// active ingredients sorted by name
  Future<List<Ingredient>> getActive() async {
    final db = await _helper.database;
    final rows = await db.query(
      'ingredients',
      where: 'is_archived = 0',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Ingredient.fromMap).toList();
  }

  /// returns the new ingredient_id
  Future<int> insert(String name, String unitOfMeasure) async {
    final db = await _helper.database;
    try {
      return await db.insert('ingredients', {
        'name': name.trim(),
        'unit_of_measure': unitOfMeasure.trim(),
        'is_archived': 0,
      });
    } on DatabaseException catch (e) {
      // name column is UNIQUE, turn the sql error into something the screen can show
      if (e.isUniqueConstraintError()) throw DuplicateNameException(name);
      rethrow;
    }
  }

  Future<void> update(Ingredient ingredient) async {
    final db = await _helper.database;
    try {
      await db.update(
        'ingredients',
        ingredient.toMap(),
        where: 'ingredient_id = ?',
        whereArgs: [ingredient.ingredientId],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw DuplicateNameException(ingredient.name);
      }
      rethrow;
    }
  }

  /// marks as archived, no delete method on purpose since past sales reference ingredients
  Future<void> archive(int ingredientId) async {
    final db = await _helper.database;
    await db.update(
      'ingredients',
      {'is_archived': 1},
      where: 'ingredient_id = ?',
      whereArgs: [ingredientId],
    );
  }
}
