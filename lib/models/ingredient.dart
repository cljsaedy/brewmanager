/// the only units the cafe uses, a dropdown so "ml" and "mL" can't both end up in the db
const List<String> kUnitsOfMeasure = ['ml', 'g', 'pcs', 'L', 'kg'];

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
