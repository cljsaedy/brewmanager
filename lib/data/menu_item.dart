import 'stock_item.dart';

// one row of the menu_items table
// there are no sizes, every size is its own menu item like "Iced Americano (Large)" (rule 6)
class MenuItem {
  const MenuItem({
    this.id,
    required this.name,
    required this.category,
    this.priceHint,
    this.noStock = false,
    this.isArchived = false,
  });

  // null for a new item that is not saved yet, the db gives the id
  final int? id;
  final String name;
  // like 'Coffee' or 'Food', typed by the owner, empty gets saved as 'Other'
  final String category;
  // optional price, only shown in the tally to help pick the right item, never added up
  final double? priceHint;
  // true = "not compared (no recipe needed)", never shows as "no recipe yet"
  final bool noStock;
  final bool isArchived;

  // makes a MenuItem from a db row
  factory MenuItem.fromRow(Map<String, Object?> row) {
    return MenuItem(
      id: row['id'] as int,
      name: row['name'] as String,
      category: row['category'] as String,
      // sqlite can give back a whole number as int, so read it as num then make it double
      priceHint: (row['price_hint'] as num?)?.toDouble(),
      noStock: row['no_stock'] == 1,
      isArchived: row['is_archived'] == 1,
    );
  }

  // turns this item into a row for the db (id and archive columns are left out, the store handles those)
  // empty category is saved as 'Other', same as stock items
  Map<String, Object?> toRow() {
    final cleanCategory = category.trim();
    return {
      'name': name.trim(),
      'category': cleanCategory.isEmpty ? defaultCategory : cleanCategory,
      'price_hint': priceHint,
      'no_stock': noStock ? 1 : 0,
    };
  }
}

// the message after a restore, names the recipe lines that could not come back
// leftOut = the archived stock items MenuItemStore.restore gave back
String restoredMessage(String name, List<String> leftOut) {
  if (leftOut.isEmpty) return 'Restored $name.';
  return 'Restored $name. Left out archived stock items: '
      '${leftOut.join(', ')}.';
}

// checks the menu item rules, gives back the first problem in plain words, or null if all good
// the store uses it before saving and the form uses it to show the message
String? menuItemProblem(MenuItem item) {
  // category and price can be empty
  if (item.name.trim().isEmpty) return 'Type a name.';
  final price = item.priceHint;
  if (price != null && price < 0) return 'Price cannot be below 0.';
  return null;
}
