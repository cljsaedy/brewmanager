import 'menu_item.dart';

/// one line of the running order, a menu item and how many
class OrderLine {
  final MenuItem menuItem;
  final int quantity;

  const OrderLine({required this.menuItem, required this.quantity});

  double get lineTotal => menuItem.sellingPrice * quantity;

  OrderLine withQuantity(int q) =>
      OrderLine(menuItem: menuItem, quantity: q);
}

/// the order being built, lives in memory only until checkout writes it
class RunningOrder {
  final List<OrderLine> lines;

  const RunningOrder({this.lines = const []});

  bool get isEmpty => lines.isEmpty;

  double get total => lines.fold<double>(0, (sum, l) => sum + l.lineTotal);

  int get itemCount => lines.fold<int>(0, (sum, l) => sum + l.quantity);

  /// menu_item_id → quantity, what the availability calculator needs to subtract
  Map<int, int> get quantityByMenuItemId => {
        for (final l in lines) l.menuItem.menuItemId: l.quantity,
      };

  /// adds one, or bumps the existing line if the item is already in the order
  RunningOrder add(MenuItem item) {
    final i = lines.indexWhere((l) => l.menuItem.menuItemId == item.menuItemId);
    if (i == -1) {
      return RunningOrder(
        lines: [...lines, OrderLine(menuItem: item, quantity: 1)],
      );
    }
    final updated = [...lines];
    updated[i] = updated[i].withQuantity(updated[i].quantity + 1);
    return RunningOrder(lines: updated);
  }

  /// removes one, dropping the line when it hits zero
  RunningOrder removeOne(int menuItemId) {
    final i = lines.indexWhere((l) => l.menuItem.menuItemId == menuItemId);
    if (i == -1) return this;

    final updated = [...lines];
    if (updated[i].quantity <= 1) {
      updated.removeAt(i);
    } else {
      updated[i] = updated[i].withQuantity(updated[i].quantity - 1);
    }
    return RunningOrder(lines: updated);
  }

  RunningOrder clear() => const RunningOrder();
}
