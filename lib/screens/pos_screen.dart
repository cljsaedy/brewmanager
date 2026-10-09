import 'package:flutter/material.dart';

import '../database/menu_item_repository.dart';
import '../database/recipe_repository.dart';
import '../database/stock_repository.dart';
import '../logic/availability_calculator.dart';
import '../models/menu_item.dart';
import '../models/order_line.dart';
import '../models/recipe_blueprint.dart';

/// the barista's till, menu grid on the left and the running order on the right
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _menuItems = MenuItemRepository();
  final _recipes = RecipeRepository();
  final _stock = StockRepository();

  List<MenuItem> _items = [];
  Map<int, List<RecipeBlueprint>> _recipesByItem = {};
  // stock totals straight from the db, before the order claims anything
  Map<int, double> _stockTotals = {};
  RunningOrder _order = const RunningOrder();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _menuItems.getActive();
    final recipes = await _recipes.getAllGroupedByMenuItem();
    final stock = await _stock.getAllBatchStock();
    if (!mounted) return;
    setState(() {
      _items = items;
      _recipesByItem = recipes;
      _stockTotals = AvailabilityCalculator.totalsByIngredient(stock);
      _loading = false;
    });
  }

  /// stock left once the current order's claims are taken out, this is what the grid checks
  /// recomputed on every order change so adding a latte also shrinks every other milk drink
  Map<int, double> get _stockAfterOrder {
    final consumed = AvailabilityCalculator.consumedByOrder(
      _order.quantityByMenuItemId,
      _recipesByItem,
    );
    return AvailabilityCalculator.totalsAfterOrder(_stockTotals, consumed);
  }

  Availability _availabilityOf(MenuItem item, Map<int, double> stockLeft) {
    return AvailabilityCalculator.forMenuItemFromTotals(
      _recipesByItem[item.menuItemId] ?? const [],
      stockLeft,
    );
  }

  void _add(MenuItem item) => setState(() => _order = _order.add(item));

  void _removeOne(int menuItemId) =>
      setState(() => _order = _order.removeOne(menuItemId));

  void _clear() => setState(() => _order = _order.clear());

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final stockLeft = _stockAfterOrder;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Point of Sale'),
        actions: [
          IconButton(
            tooltip: 'Refresh stock',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Row(
        children: [
          // left, the menu grid
          Expanded(
            flex: 2,
            child: _items.isEmpty
                ? const Center(child: Text('No menu items yet'))
                : GridView.count(
                    padding: const EdgeInsets.all(16),
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    children: [
                      for (final item in _items)
                        _MenuTile(
                          item: item,
                          availability: _availabilityOf(item, stockLeft),
                          onTap: () => _add(item),
                        ),
                    ],
                  ),
          ),
          const VerticalDivider(width: 1),
          // right, the running order
          Expanded(
            child: _OrderPanel(
              order: _order,
              onAddOne: _add,
              onRemoveOne: _removeOne,
              onClear: _clear,
            ),
          ),
        ],
      ),
    );
  }
}

/// one menu item card, dimmed with a reason when it can't be made
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.availability,
    required this.onTap,
  });

  final MenuItem item;
  final Availability availability;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = availability.canMakeAtLeastOne;

    // why it's unavailable, so the barista isn't guessing
    final reason = availability.hasNoRecipe
        ? 'No recipe set'
        : 'Out of ${availability.limitingIngredient ?? 'stock'}';

    return Card(
      // grayed out when a batch hits zero
      color: enabled ? null : Theme.of(context).disabledColor.withValues(alpha: 0.08),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: enabled ? null : Theme.of(context).disabledColor,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                '₱${item.sellingPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  color: enabled ? null : Theme.of(context).disabledColor,
                ),
              ),
              const SizedBox(height: 6),
              if (!enabled)
                Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                )
              else
                Text(
                  '${availability.servings} left',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// the running order list with total and the checkout button
class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.order,
    required this.onAddOne,
    required this.onRemoveOne,
    required this.onClear,
  });

  final RunningOrder order;
  final void Function(MenuItem) onAddOne;
  final void Function(int menuItemId) onRemoveOne;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Order (${order.itemCount})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (!order.isEmpty)
                TextButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ),
        ),
        Expanded(
          child: order.isEmpty
              ? const Center(child: Text('Tap an item to start'))
              : ListView.separated(
                  itemCount: order.lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final line = order.lines[index];
                    return ListTile(
                      title: Text(line.menuItem.name),
                      subtitle:
                          Text('₱${line.lineTotal.toStringAsFixed(2)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () =>
                                onRemoveOne(line.menuItem.menuItemId),
                          ),
                          Text('${line.quantity}',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () => onAddOne(line.menuItem),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text(
                    '₱${order.total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  // checkout is the next step, disabled for now
                  onPressed: null,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Checkout (next step)'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
