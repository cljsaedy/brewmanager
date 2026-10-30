import 'package:flutter/material.dart';

import '../logic/formatting.dart';
import '../logic/rotation_break_detector.dart';
import '../models/audit_batch.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// shown after the count is submitted and locked
///
/// this is the first time the expected figures appear, which is the whole point of
/// the blind audit, and every batch record has already been corrected to the counted value
class AuditResultsScreen extends StatelessWidget {
  const AuditResultsScreen({super.key, required this.results});

  final List<AuditResult> results;

  int get _exactCount => results.where((r) => r.isExact).length;

  /// batches short with no recorded cause, the drift the study is about
  ///
  /// a count rather than a quantity, because ml and g can't be added together
  /// and one summed number across different units would be meaningless
  int get _shortCount => results
      .where((r) => r.isDeficit && r.varianceType == VarianceType.unexplained)
      .length;

  int get _surplusCount => results
      .where((r) => r.isSurplus && r.varianceType == VarianceType.unexplained)
      .length;

  int get _receivingCount => results
      .where((r) => r.varianceType == VarianceType.unrecordedReceiving)
      .length;

  @override
  Widget build(BuildContext context) {
    // worked out from this count's variances, nothing extra was stored for it
    final rotationBreaks = RotationBreakDetector.detect(results);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Count Results'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          _buildSummary(context),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (rotationBreaks.isNotEmpty)
                  _RotationBreakSection(breaks: rotationBreaks),
                for (final result in results) _ResultRow(result: result),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                // just closes this screen, the audit screen behind it is what
                // closes the shift
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stock records updated',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'The counted amounts have replaced the system figures for all '
                  '${results.length} batches.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          _Tally(
            count: _exactCount,
            label: 'matched',
            colour: AppColors.safe,
          ),
          const SizedBox(width: AppSpacing.sm),
          _Tally(
            count: _shortCount,
            label: 'short',
            colour: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          _Tally(
            count: _surplusCount,
            label: 'over',
            colour: AppColors.caution,
          ),
          if (_receivingCount > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            _Tally(
              count: _receivingCount,
              label: 'delivery',
              colour: AppColors.info,
            ),
          ],
        ],
      ),
    );
  }
}

/// one count in the summary row
class _Tally extends StatelessWidget {
  const _Tally({
    required this.count,
    required this.label,
    required this.colour,
  });

  final int count;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    // greyed when there are none of this kind, so the eye goes to what happened
    final isZero = count == 0;

    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isZero
            ? AppColors.surfaceSunken
            : colour.withValues(alpha: 0.10),
        border: Border.all(
          color: isZero ? AppColors.hairline : colour,
        ),
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: isZero ? AppColors.inkDisabled : AppColors.ink,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isZero ? AppColors.inkDisabled : AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// probable rotation breaks, shown above the per batch list
///
/// informational only, both batches were already corrected by the write-back,
/// this just explains why the two numbers moved in opposite directions
class _RotationBreakSection extends StatelessWidget {
  const _RotationBreakSection({required this.breaks});

  final List<RotationBreak> breaks;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.infoSurface,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz, color: AppColors.onInfoSurface),
              const SizedBox(width: AppSpacing.sm),
              Text(
                breaks.length == 1
                    ? 'Possible rotation break'
                    : 'Possible rotation breaks',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.onInfoSurface),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final b in breaks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '${b.ingredientName}: batch #${b.deficit.auditBatch.batchId} is '
                '${quantity(b.deficit.variance.abs())} ${b.unitOfMeasure} short '
                'while batch #${b.surplus.auditBatch.batchId} has '
                '${quantity(b.surplus.variance.abs())} ${b.unitOfMeasure} spare. '
                'Nothing appears lost — stock was probably taken from the wrong '
                'container instead of the one expiring soonest.',
                style: const TextStyle(color: AppColors.onInfoSurface),
              ),
            ),
          Text(
            'Both batches have been corrected to the counted amounts. '
            'This is a note, not a correction.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.onInfoSurface),
          ),
        ],
      ),
    );
  }
}

/// expected against counted for one batch, the comparison the blind count was for
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final AuditResult result;

  @override
  Widget build(BuildContext context) {
    final unit = result.auditBatch.unitOfMeasure;
    final isReceiving =
        result.varianceType == VarianceType.unrecordedReceiving;

    // the same three colours the expiry matrix uses, so staff only learn one code
    final Color colour;
    if (isReceiving) {
      colour = AppColors.info;
    } else if (result.isExact) {
      colour = AppColors.safe;
    } else if (result.isDeficit) {
      colour = AppColors.danger;
    } else {
      colour = AppColors.caution;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.statusBarWidth,
            height: 40,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.auditBatch.ingredientName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Batch #${result.auditBatch.batchId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // expected and counted side by side, the comparison is the point
          Expanded(
            flex: 2,
            child: _Figure(
              label: 'Expected',
              value:
                  '${quantity(result.auditBatch.theoreticalQuantity)} $unit',
            ),
          ),
          Expanded(
            flex: 2,
            child: _Figure(
              label: 'Counted',
              value: '${quantity(result.auditedQuantity)} $unit',
              emphasise: true,
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  result.isExact
                      ? 'Matched'
                      : '${result.variance > 0 ? '+' : '−'}'
                          '${quantity(result.variance.abs())} $unit',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: colour,
                  ),
                ),
                Text(
                  _label(result),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _label(AuditResult r) {
    if (r.varianceType == VarianceType.unrecordedReceiving) {
      return 'Unrecorded delivery — records corrected';
    }
    if (r.isExact) return 'Count agreed with the records';
    return r.isDeficit ? 'Unexplained shortfall' : 'More than expected';
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppColors.inkMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
            color: emphasise ? AppColors.ink : AppColors.inkMuted,
          ),
        ),
      ],
    );
  }
}
