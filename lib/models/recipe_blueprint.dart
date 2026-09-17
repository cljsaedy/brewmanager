/// a row from recipe_blueprints joined with the ingredient's name and unit for display
class RecipeBlueprint {
  final int blueprintId;
  final int menuItemId;
  final int ingredientId;
  final double quantityRequired;
  // from the join, so the screen can show "200 ml Fresh Milk" not "ingredient 3"
  final String ingredientName;
  final String unitOfMeasure;

  const RecipeBlueprint({
    required this.blueprintId,
    required this.menuItemId,
    required this.ingredientId,
    required this.quantityRequired,
    required this.ingredientName,
    required this.unitOfMeasure,
  });

  factory RecipeBlueprint.fromMap(Map<String, Object?> map) {
    return RecipeBlueprint(
      blueprintId: map['blueprint_id'] as int,
      menuItemId: map['menu_item_id'] as int,
      ingredientId: map['ingredient_id'] as int,
      quantityRequired: (map['quantity_required'] as num).toDouble(),
      ingredientName: map['ingredient_name'] as String,
      unitOfMeasure: map['unit_of_measure'] as String,
    );
  }
}
