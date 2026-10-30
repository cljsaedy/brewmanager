/// the only units the cafe uses, a dropdown so "ml" and "mL" can't both end up in the db
const List<String> kUnitsOfMeasure = ['ml', 'g', 'pcs', 'L', 'kg'];

/// an ingredient plus what depends on it
///
/// archiving one that is still in recipes, or still has stock on the shelf, is a
/// real mistake, so the list shows both and the confirmation can name them
class IngredientUsage {
  final Ingredient ingredient;

  /// how many menu items list this ingredient
  final int recipeCount;

  /// how much is left across every batch of it
  final double stockRemaining;

  const IngredientUsage({
    required this.ingredient,
    required this.recipeCount,
    required this.stockRemaining,
  });

  factory IngredientUsage.fromMap(Map<String, Object?> map) {
    return IngredientUsage(
      ingredient: Ingredient.fromMap(map),
      recipeCount: (map['recipe_count'] as num?)?.toInt() ?? 0,
      stockRemaining: (map['stock_remaining'] as num?)?.toDouble() ?? 0,
    );
  }

  bool get hasStock => stockRemaining > 0;
  bool get isUsed => recipeCount > 0;
}

/// a row from the ingredients table, just a name and unit, stock lives in batches
class Ingredient {
  final int ingredientId;
  final String name;
  final String unitOfMeasure;
  final bool isArchived;

  const Ingredient({
    required this.ingredientId,
    required this.name,
    required this.unitOfMeasure,
    required this.isArchived,
  });

  factory Ingredient.fromMap(Map<String, Object?> map) {
    return Ingredient(
      ingredientId: map['ingredient_id'] as int,
      name: map['name'] as String,
      unitOfMeasure: map['unit_of_measure'] as String,
      isArchived: (map['is_archived'] as int) == 1,
    );
  }

  /// for update(), no id since sqflite takes that in the where clause
  Map<String, Object?> toMap() {
    return {
      'name': name,
      'unit_of_measure': unitOfMeasure,
      'is_archived': isArchived ? 1 : 0,
    };
  }
}
