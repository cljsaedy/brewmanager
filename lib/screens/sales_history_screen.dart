import 'package:flutter/material.dart';

import '../database/transaction_repository.dart';
import '../database/void_service.dart';
import '../logic/formatting.dart';
import '../models/sale.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';
import '../widgets/manager_pin_dialog.dart';

/// recorded sales, and where a sale gets voided from
///
/// list on the left and the selected sale on the right, a sale with several lines
/// doesn't fit comfortably in a dialog and the tablet is wide enough not to need one
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _transactions = TransactionRepository();
  final _voids = VoidService();

  List<Sale> _sales = [];
  Sale? _selected;
  List<SaleItem> _selectedItems = [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _transactions.getRecent();
    if (!mounted) return;

    // keep the selection if that sale is still in the list, so a void doesn't
    // throw the manager back to nothing selected
    final keep = _selected == null
        ? null
        : list.where((s) => s.transactionId == _selected!.transactionId).firstOrNull;

    setState(() {
      _sales = list;
      _selected = keep;
      _loading = false;
      _working = false;
    });

    if (keep != null) await _loadItems(keep);
  }

  Future<void> _select(Sale sale) async {
    setState(() => _selected = sale);
    await _loadItems(sale);
  }

  Future<void> _loadItems(Sale sale) async {
    final items = await _transactions.getItems(sale.transactionId);
    if (!mounted) return;
    setState(() => _selectedItems = items);
  }

  Future<void> _void(Sale sale) async {
    if (_working) return;

    // voiding puts stock back, so it needs manager approval not just a barista tap
    final manager = await ManagerPinDialog.show(
      context,
      'Void sale #${sale.transactionId} (${money(sale.totalAmount)}) and '
      'return its ingredients to stock?',
    );
    if (manager == null) return;

    setState(() => _working = true);

    try {
      final restored = await _voids.voidTransaction(
        transactionId: sale.transactionId,
        managerUserId: manager.userId,
      );
      await _reload();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _RestoredDialog(
          transactionId: sale.transactionId,
          restored: restored,
        ),
      );
    } on AlreadyVoidedException {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That sale was already voided')),
      );
    }
  }

  /// sales grouped by calendar day, newest day first
  ///
  /// a week of trading is a long undifferentiated list otherwise
  List<(String, List<Sale>)> get _byDay {
    final groups = <String, List<Sale>>{};
    for (final sale in _sales) {
      final day = sale.transactionDatetime.substring(0, 10);
      groups.putIfAbsent(day, () => []).add(sale);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final day in days) (day, groups[day]!)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No sales recorded yet',
                  message: 'Sales appear here as soon as the first order is '
                      'rung up at the till.',
                )
              : Row(
                  children: [
                    Expanded(flex: 3, child: _buildList()),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 2, child: _buildDetail()),
                  ],
                ),
    );
  }

  Widget _buildList() {
    return ListView(
      children: [
        for (final (day, sales) in _byDay) ...[
          _DayHeader(day: day, sales: sales),
          for (final sale in sales)
            _SaleRow(
              sale: sale,
              selected: sale.transactionId == _selected?.transactionId,
              onTap: () => _select(sale),
            ),
        ],
      ],
    );
  }

  Widget _buildDetail() {
    final sale = _selected;

    if (sale == null) {
      return Container(
        color: AppColors.surfaceSunken,
        child: const EmptyState(
          icon: Icons.touch_app_outlined,
          title: 'No sale selected',
          message: 'Pick a sale on the left to see what was sold and to void it.',
        ),
      );
    }

    return Container(
      color: AppColors.surfaceSunken,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sale #${sale.transactionId}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${_formatDateTime(sale.transactionDatetime)} · '
                  '${sale.cashierName} · shift #${sale.shiftId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (sale.isVoided) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.10),
                      border: Border.all(color: AppColors.danger),
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.cancel_outlined, color: AppColors.danger),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Voided. Its ingredients were returned to the '
                            'batches they came from.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (final item in _selectedItems)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${item.quantity}×',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.menuItemName,
                                style:
                                    Theme.of(context).textTheme.titleMedium,
                              ),
                              // the price it sold at, not today's menu price
                              Text(
                                '${money(item.unitPriceAtSale)} each at the '
                                'time of sale',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          money(item.lineTotal),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
              ],
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
                      money(sale.totalAmount),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: sale.isVoided
                            ? AppColors.inkDisabled
                            : AppColors.ink,
                        decoration:
                            sale.isVoided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
                if (!sale.isVoided) ...[
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                      ),
                      onPressed: _working ? null : () => _void(sale),
                      icon: const Icon(Icons.undo),
                      label: const Text('Void this sale'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ISO-8601 is long, trim it to date and time for display
  String _formatDateTime(String iso) {
    final d = DateTime.parse(iso);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

/// a day's heading with what that day took, voided sales left out of the total
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.sales});

  final String day;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final counted = sales.where((s) => !s.isVoided);
    final total = counted.fold<double>(0, (sum, s) => sum + s.totalAmount);

    return Container(
      color: AppColors.surfaceSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(day, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(
            '${counted.length} sale${counted.length == 1 ? '' : 's'} · '
            '${money(total)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({
    required this.sale,
    required this.selected,
    required this.onTap,
  });

  final Sale sale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = sale.transactionDatetime.substring(11, 16);

    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.surfaceSunken : null,
        border: const Border(
          bottom: BorderSide(color: AppColors.hairline),
        ),
      ),
      child: ListTile(
        // a left bar rather than a different background, the selected row already
        // uses the tint
        leading: Container(
          width: AppSizes.statusBarWidth,
          height: 32,
          decoration: BoxDecoration(
            color: sale.isVoided
                ? AppColors.danger
                : (selected ? AppColors.ink : AppColors.hairline),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Row(
          children: [
            Text(
              '$time · ${money(sale.totalAmount)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    decoration:
                        sale.isVoided ? TextDecoration.lineThrough : null,
                    color:
                        sale.isVoided ? AppColors.inkDisabled : null,
                  ),
            ),
            if (sale.isVoided) ...[
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'VOIDED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.danger,
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          'Sale #${sale.transactionId} · '
          '${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'} · '
          '${sale.cashierName}',
        ),
        onTap: onTap,
      ),
    );
  }
}

/// shows which batch each amount went back into, proof the reversal was exact
///
/// this is only possible because every deduction was written as its own row
/// naming its batch, so a reversal never has to guess
class _RestoredDialog extends StatelessWidget {
  const _RestoredDialog({
    required this.transactionId,
    required this.restored,
  });

  final int transactionId;
  final List<RestoredBatch> restored;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.undo, size: 40),
      title: Text('Sale #$transactionId voided'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Returned to stock:'),
            const SizedBox(height: AppSpacing.md),
            if (restored.isEmpty)
              const Text(
                'Nothing to return — this sale deducted no ingredients.',
              ),
            for (final r in restored)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.east, size: 18,
                        color: AppColors.inkMuted),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${quantity(r.quantity)} ${r.unitOfMeasure} '
                        '${r.ingredientName}',
                      ),
                    ),
                    Text(
                      'batch #${r.batchId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
