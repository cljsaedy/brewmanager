import 'package:flutter/material.dart';

import '../database/checkout_service.dart';
import '../database/menu_item_repository.dart';
import '../database/recipe_repository.dart';
import '../database/shift_repository.dart';
import '../database/stock_repository.dart';
import '../database/suggestion_repository.dart';
import '../logic/availability_calculator.dart';
import '../logic/fefo_engine.dart' show BatchStock;
import '../logic/formatting.dart';
import '../logic/suggestion_engine.dart';
import '../models/menu_item.dart';
import '../models/order_line.dart';
import '../models/recipe_blueprint.dart';
import '../session/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/suggestion_banner.dart';
import 'receipt_screen.dart';

/// the barista's till, menu on the left and the running order on the right
///
/// three columns rather than four, the tablet is only 1006 wide and a wider tile
/// means the name is readable standing at the counter, which matters more than
/// fitting one extra item on screen
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _menuItems = MenuItemRepository();
  final _recipes = RecipeRepository();
  final _stock = StockRepository();
  final _checkout = CheckoutService();
  final _suggestions = SuggestionRepository();
  final _shifts = ShiftRepository();

  List<MenuItem> _items = [];
  Map<int, List<RecipeBlueprint>> _recipesByItem = {};
  // usable stock totals straight from the db, before the order claims anything
  Map<int, double> _stockTotals = {};
  // stock that exists but has expired, so a blocked tile can say which it is
  Map<int, double> _expiredTotals = {};
  RunningOrder _order = const RunningOrder();
  bool _loading = true;
  bool _checkingOut = false;

  Suggestion? _suggestion;
  bool _isColdStart = false;
  // the suggestion_logs row for the suggestion on screen, so acceptance can be marked
  int? _suggestionLogId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final items = await _menuItems.getActive();
    final recipes = await _recipes.getAllGroupedByMenuItem();
    // usable only, expired stock cannot be sold so it must not count toward
    // what the grid says can be made
    final stock = await _stock.getAllBatchStock();
    final expired = await _stock.getExpiredTotals();
    if (!mounted) return;
    setState(() {
      _items = items;
      _recipesByItem = recipes;
      _stockTotals = AvailabilityCalculator.totalsByIngredient(stock);
      _expiredTotals = expired;
      _loading = false;
    });

    await _refreshSuggestion(stock);
  }

  /// ranks the menu and logs whatever ends up on the banner
  ///
  /// logged once per load rather than on every rebuild, otherwise the log would
  /// fill up with the same suggestion over and over
  Future<void> _refreshSuggestion(Map<int, List<BatchStock>> stock) async {
    final user = Session.currentUser;
    if (user == null) return;

    final candidates = await _suggestions.loadCandidates();
    final ranking = SuggestionEngine.rank(
      candidates: candidates,
      stockByIngredient: stock,
      today: DateTime.now(),
    );

    final top = ranking.top;
    if (top == null) {
      if (!mounted) return;
      setState(() {
        _suggestion = null;
        _suggestionLogId = null;
      });
      return;
    }

    // only log against a shift that is genuinely open
    //
    // suggestion_logs.shift_id is NOT NULL, and this used to call
    // getOrCreateOpenShift, which meant just looking at the till opened a shift
    // nobody asked for, a suggestion outside a shift belongs to no shift's record
    final openShift = await _shifts.getOpenShift();
    final logId = openShift == null
        ? null
        : await _suggestions.logSuggestion(
            shiftId: openShift.shiftId,
            suggestion: top,
          );

    if (!mounted) return;
    setState(() {
      _suggestion = top;
      _isColdStart = ranking.isColdStart;
      _suggestionLogId = logId;
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
      isIngredientTracked: item.isIngredientTracked,
      expiredByIngredient: _expiredTotals,
    );
  }

  Future<void> _add(MenuItem item) async {
    setState(() => _order = _order.add(item));

    // adding the suggested item counts as accepting it however it was tapped,
    // from the banner or straight off the grid, what matters is that it sold
    final logId = _suggestionLogId;
    if (logId != null && item.menuItemId == _suggestion?.menuItem.menuItemId) {
      _suggestionLogId = null; // only mark it once
      await _suggestions.markAccepted(logId);
    }
  }

  void _removeOne(int menuItemId) =>
      setState(() => _order = _order.removeOne(menuItemId));

  void _clear() => setState(() => _order = _order.clear());

  /// the banner's add button, _add does the acceptance marking
  void _acceptSuggestion() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    _add(suggestion.menuItem);
  }

  Future<void> _doCheckout() async {
    final user = Session.currentUser;
    if (_order.isEmpty || _checkingOut || user == null) return;

    setState(() => _checkingOut = true);

    // keep a copy for the receipt, the running order is cleared right after the sale
    final soldLines = _order.lines;

    try {
      final result = await _checkout.checkout(_order, user.userId);
      if (!mounted) return;

      setState(() {
        _order = _order.clear();
        _checkingOut = false;
      });
      // reload so the grid shows the stock that's actually left
      await _reload();
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            transactionId: result.transactionId,
            lines: soldLines,
            total: result.total,
            soldAt: DateTime.now(),
            cashierName: user.name,
          ),
        ),
      );
    } on InsufficientStockException catch (e) {
      // nothing was written, the transaction rolled back
      if (!mounted) return;
      setState(() => _checkingOut = false);
      await _reload();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(
            'Sale cancelled — short ${quantity(e.shortfall)} ${e.unit} '
            'of ${e.ingredientName}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Point of Sale')),
        body: const Center(child: CircularProgressIndicator()),
      );
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
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Row(
        children: [
          // left, the menu
          Expanded(
            flex: 2,
            child: Column(
              children: [
                if (_suggestion != null)
                  SuggestionBanner(
                    suggestion: _suggestion!,
                    isColdStart: _isColdStart,
                    onTap: _acceptSuggestion,
                  ),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('No menu items yet'))
                      : GridView.count(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          crossAxisCount: 3,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 1.35,
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
              ],
            ),
          ),
          // right, the order, on the sunken surface so it reads as its own zone
          SizedBox(
            width: 330,
            child: _OrderPanel(
              order: _order,
              checkingOut: _checkingOut,
              onAddOne: _add,
              onRemoveOne: _removeOne,
              onClear: _clear,
              onCheckout: _doCheckout,
            ),
          ),
        ],
      ),
    );
  }
}

/// one menu item, the name is the biggest thing because that's what gets tapped
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

    // say why, a tile that just dims leaves the barista guessing
    final ingredient = availability.limitingIngredient ?? 'stock';
    final reason = availability.hasNoRecipe
        ? 'No recipe set'
        // expired stock is on the shelf but unsellable, so saying "out of" it
        // would contradict the stock screen
        : availability.blockedByExpiry
        ? '$ingredient expired'
        : 'Out of $ingredient';

    return Card(
      color: enabled ? AppColors.surfaceRaised : AppColors.surfaceSunken,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: enabled ? AppColors.inkBody : AppColors.inkDisabled,
                    height: 1.15,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      money(item.sellingPrice),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: enabled
                            ? AppColors.inkMuted
                            : AppColors.inkDisabled,
                      ),
                    ),
                  ),
                  if (enabled && !availability.hasServingLimit)
                    // food sold as a whole unit, there is no stock to count down
                    Text(
                      'not stocked',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else if (enabled)
                    Text(
                      '${availability.servings} left',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    Expanded(
                      child: Text(
                        reason,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// the running order, with the total as the largest text in the working app
/// because it is the number said out loud to the customer
class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.order,
    required this.checkingOut,
    required this.onAddOne,
    required this.onRemoveOne,
    required this.onClear,
    required this.onCheckout,
  });

  final RunningOrder order;
  final bool checkingOut;
  final void Function(MenuItem) onAddOne;
  final void Function(int menuItemId) onRemoveOne;
  final VoidCallback onClear;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSunken,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    order.isEmpty
                        ? 'Order'
                        : 'Order · ${order.itemCount} '
                              'item${order.itemCount == 1 ? '' : 's'}',
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
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'Tap an item to start the order',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkMuted),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: order.lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _OrderRow(
                      line: order.lines[index],
                      onAddOne: onAddOne,
                      onRemoveOne: onRemoveOne,
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Expanded(
                      child: Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                    Text(
                      money(order.total),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    // disabled while a sale is being written so a second tap can't queue one
                    onPressed: order.isEmpty || checkingOut ? null : onCheckout,
                    icon: const Icon(Icons.point_of_sale),
                    label: Text(checkingOut ? 'Recording…' : 'Checkout'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// two lines per order line, a single row can't fit a name and a stepper in 330px
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.line,
    required this.onAddOne,
    required this.onRemoveOne,
  });

  final OrderLine line;
  final void Function(MenuItem) onAddOne;
  final void Function(int menuItemId) onRemoveOne;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.menuItem.name,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              // the price on its own, the running total at the bottom of the
              // panel is what gets checked and the receipt keeps the line totals
              Text(
                money(line.menuItem.sellingPrice),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              _QtyButton(
                icon: Icons.remove,
                onTap: () => onRemoveOne(line.menuItem.menuItemId),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  '${line.quantity}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _QtyButton(icon: Icons.add, onTap: () => onAddOne(line.menuItem)),
            ],
          ),
        ],
      ),
    );
  }
}

/// a square tap target rather than a bare icon, easier to hit in a hurry
class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.hairline),
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        child: Icon(icon, size: 22, color: AppColors.ink),
      ),
    );
  }
}
