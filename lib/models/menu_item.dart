/// a row from the menu_items table
class MenuItem {
  final int menuItemId;
  final String name;
  // current price only, sales copy this onto the line item so price edits don't change history
  final double sellingPrice;
  final bool isArchived;

  const MenuItem({
    required this.menuItemId,
    required this.name,
    required this.sellingPrice,
    required this.isArchived,
  });

  factory MenuItem.fromMap(Map<String, Object?> map) {
    return MenuItem(
      menuItemId: map['menu_item_id'] as int,
      name: map['name'] as String,
      // sqlite gives back int if the number is whole (e.g. 120 not 120.0), so convert safely
      sellingPrice: (map['selling_price'] as num).toDouble(),
      isArchived: (map['is_archived'] as int) == 1,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'selling_price': sellingPrice,
      'is_archived': isArchived ? 1 : 0,
    };
  }
}
