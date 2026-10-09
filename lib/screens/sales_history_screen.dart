import 'package:flutter/material.dart';

import '../database/transaction_repository.dart';
import '../database/void_service.dart';
import '../models/sale.dart';
import '../widgets/manager_pin_dialog.dart';

/// list of recorded sales, where a sale gets voided from
class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  final _transactions = TransactionRepository();
  final _voids = VoidService();

  List<Sale> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _transactions.getRecent();
    if (!mounted) return;
    setState(() {
      _sales = list;
      _loading = false;
    });
  }

  Future<void> _openDetail(Sale sale) async {
    final items = await _transactions.getItems(sale.transactionId);
    if (!mounted) return;

    final shouldVoid = await showDialog<bool>(
      context: context,
      builder: (_) => _SaleDetailDialog(sale: sale, items: items),
    );
    if (shouldVoid != true) return;
    if (!mounted) return;

    await _void(sale);
  }

  Future<void> _void(Sale sale) async {
    // voiding puts stock back, so it needs manager approval not just a barista tap
    final manager = await ManagerPinDialog.show(
      context,
      'Void sale #${sale.transactionId} '
      '(₱${sale.totalAmount.toStringAsFixed(2)}) and return its ingredients to stock?',
    );
    if (manager == null) return;

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
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? const Center(child: Text('No sales recorded yet'))
              : ListView.separated(
                  itemCount: _sales.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final sale = _sales[index];
                    return ListTile(
                      leading: Icon(
                        sale.isVoided
                            ? Icons.cancel_outlined
                            : Icons.receipt_long_outlined,
                        color: sale.isVoided
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      title: Text(
                        'Sale #${sale.transactionId} · '
                        '₱${sale.totalAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          // struck through so a voided sale reads as voided at a glance
                          decoration:
                              sale.isVoided ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        '${_formatDateTime(sale.transactionDatetime)} · '
                        '${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'} · '
                        '${sale.cashierName}'
                        '${sale.isVoided ? ' · VOIDED' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDetail(sale),
                    );
                  },
                ),
    );
  }

  // ISO-8601 is long, trim it to date and time for the list
  String _formatDateTime(String iso) {
    final d = DateTime.parse(iso);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

/// what was on the sale, with a void button when it isn't voided yet
class _SaleDetailDialog extends StatelessWidget {
  const _SaleDetailDialog({required this.sale, required this.items});

  final Sale sale;
  final List<SaleItem> items;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Sale #${sale.transactionId}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sale.isVoided)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'This sale was voided and its stock returned.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text('${item.quantity}×'),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.menuItemName)),
                    // the price it sold at, not today's menu price
                    Text('₱${item.lineTotal.toStringAsFixed(2)}'),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              children: [
                const Text('Total'),
                const Spacer(),
                Text(
                  '₱${sale.totalAmount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!sale.isVoided)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void sale'),
          ),
      ],
    );
  }
}

/// shows which batch each amount went back into, proof the reversal was exact
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
      title: Text('Sale #$transactionId voided'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Returned to stock:'),
            const SizedBox(height: 8),
            if (restored.isEmpty)
              const Text('Nothing to return — this sale deducted no ingredients.'),
            for (final r in restored)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• ${_fmt(r.quantity)} ${r.unitOfMeasure} '
                  '${r.ingredientName} → batch #${r.batchId}',
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

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
