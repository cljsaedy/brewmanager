import 'package:flutter/material.dart';

import '../logic/rotation_break_detector.dart';
import '../models/audit_batch.dart';

/// shown after the count is submitted and locked
///
/// this is the first time the expected figures appear, which is the whole point of
/// the blind audit, and every batch record has already been corrected to the counted value
class AuditResultsScreen extends StatelessWidget {
  const AuditResultsScreen({super.key, required this.results});

  final List<AuditResult> results;

  /// unexplained shortfall only, surpluses and unrecorded deliveries are not waste
  double get _unexplainedLoss {
    return results
        .where((r) =>
            r.isDeficit && r.varianceType == VarianceType.unexplained)
        .fold<double>(0, (sum, r) => sum + r.variance.abs());
  }

  int get _exactCount => results.where((r) => r.isExact).length;

  @override
  Widget build(BuildContext context) {
    final withVariance = results.where((r) => !r.isExact).toList();
    // worked out from this count's variances, nothing extra was stored for it
    final rotationBreaks = RotationBreakDetector.detect(results);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Count Results'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock records updated',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${results.length} batches counted · '
                      '$_exactCount matched exactly · '
                      '${withVariance.length} with a difference',
                    ),
                    if (_unexplainedLoss > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Unexplained shortfall recorded for this shift.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (rotationBreaks.isNotEmpty)
                  _RotationBreakSection(breaks: rotationBreaks),
                for (final result in results) ...[
                  _ResultRow(result: result),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                // just closes this screen, the audit screen behind it is what closes the shift
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
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
      color: Theme.of(context).colorScheme.tertiaryContainer,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz),
              const SizedBox(width: 8),
              Text(
                breaks.length == 1
                    ? 'Possible rotation break'
                    : 'Possible rotation breaks',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final b in breaks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${b.ingredientName}: batch #${b.deficit.auditBatch.batchId} is '
                '${_fmt(b.deficit.variance.abs())} ${b.unitOfMeasure} short while '
                'batch #${b.surplus.auditBatch.batchId} has '
                '${_fmt(b.surplus.variance.abs())} ${b.unitOfMeasure} spare. '
                'Nothing appears lost — stock was probably taken from the wrong '
                'container instead of the one expiring soonest.',
              ),
            ),
          Text(
            'Both batches have been corrected to the counted amounts. '
            'This is a note, not a correction.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// expected vs counted vs difference for one batch
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final AuditResult result;

  @override
  Widget build(BuildContext context) {
    final unit = result.auditBatch.unitOfMeasure;
    final isReceiving =
        result.varianceType == VarianceType.unrecordedReceiving;

    // green for a match, red for a shortfall, amber for a surplus
    final Color colour;
    if (result.isExact) {
      colour = const Color(0xFF2E7D32);
    } else if (result.isDeficit) {
      colour = Theme.of(context).colorScheme.error;
    } else {
      colour = const Color(0xFFF9A825);
    }

    return ListTile(
      leading: Container(
        width: 8,
        height: 44,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      title: Text(
        '${result.auditBatch.ingredientName} · batch #${result.auditBatch.batchId}',
      ),
      subtitle: Text(
        'Expected ${_fmt(result.auditBatch.theoreticalQuantity)} $unit · '
        'counted ${_fmt(result.auditedQuantity)} $unit\n'
        '${_varianceLabel(result, unit)}',
      ),
      isThreeLine: true,
      trailing: isReceiving
          // kept out of loss totals, it is a bookkeeping correction not waste
          ? const Chip(label: Text('Unrecorded\ndelivery'))
          : null,
    );
  }

  String _varianceLabel(AuditResult r, String unit) {
    if (r.isExact) return 'Matched exactly';
    final amount = '${_fmt(r.variance.abs())} $unit';
    if (r.varianceType == VarianceType.unrecordedReceiving) {
      return '$amount more than recorded — records corrected';
    }
    return r.isDeficit
        ? '$amount short — unexplained'
        : '$amount more than expected — unexplained';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
