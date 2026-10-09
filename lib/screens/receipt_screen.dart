import 'package:flutter/material.dart';

import '../models/order_line.dart';

/// on screen receipt shown right after a sale, no printing (out of scope, screen only)
/// takes the order as it was at checkout since the running order is cleared straight after
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({
    super.key,
    required this.transactionId,
    required this.lines,
    required this.total,
    required this.soldAt,
    required this.cashierName,
  });

  final int transactionId;
  final List<OrderLine> lines;
  final double total;
  final DateTime soldAt;
  final String cashierName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        // no back arrow, done is the only way out so the barista can't go back to a sold order
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Small House Cafe',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Sale #$transactionId',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '${_formatDateTime(soldAt)} · $cashierName',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 28),

                  // the sold lines, scrolls if the order was long
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final line in lines)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Text('${line.quantity}×'),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(line.menuItem.name)),
                                  Text('₱${line.lineTotal.toStringAsFixed(2)}'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const Divider(height: 28),
                  Row(
                    children: [
                      Text(
                        'Total',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        '₱${total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 2026-10-09 14:30, built by hand so we don't need a date package
  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
