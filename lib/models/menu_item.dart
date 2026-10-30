/// a row from the menu_items table
class MenuItem {
  final int menuItemId;
  final String name;
  // current price only, sales copy this onto the line item so price edits don't change history
  final double sellingPrice;
  final bool isArchived;

  /// whether this is made from ingredients the system deducts and audits
  ///
  /// true for drinks, which have a recipe and move stock on every sale
  ///
  /// false for prepared food sold as a whole unit, a croissant or a sandwich,
  /// which the study's scope says can be sold through the till but is not
  /// tracked at ingredient level
  ///
  /// the distinction has to be stated rather than guessed from whether a recipe
  /// exists, otherwise a drink whose recipe nobody set would be mistaken for
  /// food and would sell without deducting anything
  final bool isIngredientTracked;

  const MenuItem({
    required this.menuItemId,
    required this.name,
    required this.sellingPrice,
    required this.isArchived,
    this.isIngredientTracked = true,
  });

  factory MenuItem.fromMap(Map<String, Object?> map) {
    return MenuItem(
      menuItemId: map['menu_item_id'] as int,
      name: map['name'] as String,
      // sqlite gives back int if the number is whole (e.g. 120 not 120.0), so convert safely
      sellingPrice: (map['selling_price'] as num).toDouble(),
      isArchived: (map['is_archived'] as int) == 1,
      // defaults to tracked, which is what every row was before the column existed
      isIngredientTracked: (map['is_ingredient_tracked'] as int?) != 0,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'selling_price': sellingPrice,
      'is_archived': isArchived ? 1 : 0,
      'is_ingredient_tracked': isIngredientTracked ? 1 : 0,
    };
  }

  /// food sold as a whole unit, no recipe and nothing deducted
  bool get isWholeUnit => !isIngredientTracked;
}
