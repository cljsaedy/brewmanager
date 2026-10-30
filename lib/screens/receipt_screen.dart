import 'package:flutter/material.dart';

import '../logic/formatting.dart';
import '../models/order_line.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// on screen receipt shown right after a sale
///
/// no printing, that's out of scope, so this is what the customer is shown and
/// it is laid out like a receipt rather than like another app screen, narrow
/// column, amounts in a right hand column, the total unmissable
///
/// takes the order as it was at checkout since the running order is cleared
/// straight after
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

  int get _itemCount => lines.fold<int>(0, (sum, l) => sum + l.quantity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceSunken,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              children: [
                Expanded(
                  child: Card(
                    child: Column(
                      children: [
                        _buildHeader(context),
                        const Divider(height: 1),
                        Expanded(child: _buildLines(context)),
                        const Divider(height: 1),
                        _buildTotal(context),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 36,
            color: AppColors.safe,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Small House Cafe',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sale #$transactionId · ${_formatDateTime(soldAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Served by $cashierName',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildLines(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // fixed width so the names line up down the receipt
                SizedBox(
                  width: 36,
                  child: Text(
                    '${line.quantity}×',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.menuItem.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (line.quantity > 1)
                        Text(
                          '${money(line.menuItem.sellingPrice)} each',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Text(
                  money(line.lineTotal),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTotal(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '$_itemCount item${_itemCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                money(total),
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 2026-10-14 14:30, built by hand so we don't need a date package
  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
