import 'package:flutter/material.dart';

import '../services/home_status_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// the three tiles across the top of both home screens
///
/// each one is information and a way in, tapping a tile goes to the screen it
/// describes, so the band earns its space instead of being decoration
class StatusBand extends StatelessWidget {
  const StatusBand({
    super.key,
    required this.status,
    required this.onShiftTap,
    required this.onSalesTap,
    required this.onStockTap,
  });

  final HomeStatus status;
  final VoidCallback onShiftTap;
  final VoidCallback onSalesTap;
  final VoidCallback onStockTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _shiftTile(context)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _salesTile(context)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _stockTile(context)),
      ],
    );
  }

  Widget _shiftTile(BuildContext context) {
    final shift = status.openShift;

    if (shift == null) {
      return _Tile(
        label: 'Shift',
        value: 'Not open',
        detail: 'Open one to start recording',
        onTap: onShiftTap,
      );
    }

    final opened = DateTime.parse(shift.openedAt);
    final elapsed = DateTime.now().difference(opened);
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;

    return _Tile(
      label: 'Shift',
      value: shift.userName,
      detail: hours > 0
          ? 'Open ${hours}h ${minutes}m'
          : 'Open ${minutes}m',
      accent: AppColors.safe,
      onTap: onShiftTap,
    );
  }

  Widget _salesTile(BuildContext context) {
    final summary = status.shiftSummary;

    if (summary == null) {
      return _Tile(
        label: 'This shift',
        value: '—',
        detail: 'No shift open',
        onTap: onSalesTap,
      );
    }

    return _Tile(
      label: 'This shift',
      value: '₱${summary.salesTotal.toStringAsFixed(0)}',
      detail: '${summary.saleCount} '
          'sale${summary.saleCount == 1 ? '' : 's'}'
          '${summary.declaredLossCount > 0 ? ' · ${summary.declaredLossCount} loss' : ''}',
      onTap: onSalesTap,
    );
  }

  Widget _stockTile(BuildContext context) {
    // the label stays the same whatever the state, so staff learn one tile
    // rather than reading a heading that moves around on them
    const label = 'Expiring soon';

    // the one thing worth noticing on walking up to the tablet
    if (status.hasUrgentStock) {
      return _Tile(
        label: label,
        value: '${status.urgentBatchCount} '
            'batch${status.urgentBatchCount == 1 ? '' : 'es'}',
        detail: status.soonestIngredient == null
            ? 'Expiring within 2 days'
            : '${status.soonestIngredient} '
                '${_daysLabel(status.soonestDays!)}',
        accent: AppColors.danger,
        emphasise: true,
        onTap: onStockTap,
      );
    }

    return _Tile(
      label: label,
      value: 'None',
      detail: status.soonestDays == null
          ? 'No stock on hand'
          : 'Soonest ${_daysLabel(status.soonestDays!)}',
      accent: AppColors.safe,
      onTap: onStockTap,
    );
  }

  static String _daysLabel(int days) {
    if (days < 0) return 'expired';
    if (days == 0) return 'expires today';
    if (days == 1) return 'expires tomorrow';
    return 'expires in $days days';
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    required this.detail,
    required this.onTap,
    this.accent,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final String detail;
  final VoidCallback onTap;

  /// a thin bar down the left, the only colour on the tile
  final Color? accent;

  /// fills the tile with the accent tint, used when something needs attention
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final accentColour = accent;

    return Card(
      color: emphasise && accentColour != null
          ? accentColour.withValues(alpha: 0.08)
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              if (accentColour != null) ...[
                Container(
                  width: AppSizes.statusBarWidth,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColour,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
