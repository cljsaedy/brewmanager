import 'package:flutter/material.dart';

import '../database/batch_repository.dart';
import '../logic/expiry_risk.dart';
import '../logic/formatting.dart';
import '../logic/stock_grouping.dart';
import '../models/inventory_batch.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import 'batch_correction_dialog.dart';

/// stock on hand, colour coded by how close the expiry is
///
/// two sort modes because the screen answers two different questions, "how much
/// milk do i have" wants batches gathered under their ingredient, "what needs
/// using today" wants everything in expiry order whatever it is
class ExpiryMatrixScreen extends StatefulWidget {
  const ExpiryMatrixScreen({super.key});

  @override
  State<ExpiryMatrixScreen> createState() => _ExpiryMatrixScreenState();
}

enum _SortMode { byIngredient, byExpiry }

class _ExpiryMatrixScreenState extends State<ExpiryMatrixScreen> {
  final _batches = BatchRepository();

  List<BatchWithIngredient> _withStock = [];
  List<BatchWithIngredient> _depleted = [];
  bool _loading = true;
  bool _showDepleted = false;
  _SortMode _sort = _SortMode.byIngredient;

  // read once per load so every row on screen is judged against the same date
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await _batches.getAllWithIngredient(includeDepleted: true);
    if (!mounted) return;
    setState(() {
      _today = DateTime.now();
      _withStock = all.where((b) => b.batch.quantityRemaining > 0).toList();
      _depleted = all.where((b) => b.batch.quantityRemaining <= 0).toList();
      _loading = false;
    });
  }

  /// fixes figures that were entered wrongly at receiving
  ///
  /// the only honest route for a typo, the alternatives are recording stock that
  /// never existed as waste or letting the closing count report it as drift
  Future<void> _correct(BatchWithIngredient item) async {
    final changed = await BatchCorrectionDialog.show(context, item);
    if (changed == true) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Batch #${item.batch.batchId} corrected'),
        ),
      );
    }
  }

  /// how many batches sit in each band, for the summary chips
  Map<ExpiryBand, int> get _counts {
    final counts = {
      ExpiryBand.red: 0,
      ExpiryBand.yellow: 0,
      ExpiryBand.green: 0,
    };
    for (final item in _withStock) {
      final band = ExpiryRisk.bandFor(item.batch.expiryDate, _today);
      counts[band] = counts[band]! + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock & Expiry')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock & Expiry'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          _buildControls(),
          const Divider(height: 1),
          Expanded(
            child: _withStock.isEmpty && _depleted.isEmpty
                ? const Center(child: Text('No batches recorded yet'))
                : ListView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    children: [
                      if (_sort == _SortMode.byIngredient)
                        ..._buildGrouped()
                      else
                        ..._buildFlat(),
                      if (_depleted.isNotEmpty) _buildDepletedSection(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// the band counts and the sort toggle share one row to save vertical space
  Widget _buildControls() {
    final counts = _counts;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          _BandChip(
            band: ExpiryBand.red,
            count: counts[ExpiryBand.red]!,
            label: 'Use now',
          ),
          const SizedBox(width: AppSpacing.sm),
          _BandChip(
            band: ExpiryBand.yellow,
            count: counts[ExpiryBand.yellow]!,
            label: 'This week',
          ),
          const SizedBox(width: AppSpacing.sm),
          _BandChip(
            band: ExpiryBand.green,
            count: counts[ExpiryBand.green]!,
            label: 'Fine',
          ),
          const Spacer(),
          SegmentedButton<_SortMode>(
            segments: const [
              ButtonSegment(
                value: _SortMode.byIngredient,
                label: Text('By ingredient'),
              ),
              ButtonSegment(
                value: _SortMode.byExpiry,
                label: Text('By expiry'),
              ),
            ],
            selected: {_sort},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _sort = s.first),
          ),
        ],
      ),
    );
  }

  /// grouped under each ingredient with a running total per group
  List<Widget> _buildGrouped() {
    final groups = StockGrouping.byIngredient(_withStock, _today);

    return [
      for (final group in groups) ...[
        _GroupHeader(group: group, today: _today),
        for (final item in group.batches)
          _BatchRow(
            item: item,
            today: _today,
            indented: true,
            onCorrect: () => _correct(item),
          ),
      ],
    ];
  }

  /// flat, soonest expiry first, for answering what is urgent right now
  List<Widget> _buildFlat() {
    final sorted = [..._withStock]..sort(
        (a, b) => a.batch.expiryDate.compareTo(b.batch.expiryDate),
      );

    return [
      for (final item in sorted)
        _BatchRow(
          item: item,
          today: _today,
          onCorrect: () => _correct(item),
        ),
    ];
  }

  /// collapsed, kept because empty containers are still on the shelf and get
  /// counted at the closing audit
  Widget _buildDepletedSection() {
    return Column(
      children: [
        const Divider(height: 1),
        ListTile(
          leading: Icon(
            _showDepleted ? Icons.expand_less : Icons.expand_more,
          ),
          title: Text('Used up (${_depleted.length})'),
          onTap: () => setState(() => _showDepleted = !_showDepleted),
        ),
        if (_showDepleted)
          for (final item in _depleted)
            _BatchRow(
              item: item,
              today: _today,
              depleted: true,
              onCorrect: () => _correct(item),
            ),
      ],
    );
  }
}

/// one band's count, the fill is the bright colour and the number the dark one
class _BandChip extends StatelessWidget {
  const _BandChip({
    required this.band,
    required this.count,
    required this.label,
  });

  final ExpiryBand band;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colour = bandColour(band);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        border: Border.all(color: colour),
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      child: Row(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              // the text variant, the fill already carries the bright colour
              color: bandTextColour(band),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// the ingredient's name and everything left of it, the number being looked up
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.today});

  final IngredientStockGroup group;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.statusBarWidth,
            height: 28,
            decoration: BoxDecoration(
              color: bandColour(group.worstBand),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              group.ingredientName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Text(
            '${quantity(group.totalQuantity)} ${group.unitOfMeasure}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'in ${group.batchCount} batch${group.batchCount == 1 ? '' : 'es'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// one batch
class _BatchRow extends StatelessWidget {
  const _BatchRow({
    required this.item,
    required this.today,
    required this.onCorrect,
    this.depleted = false,
    this.indented = false,
  });

  final BatchWithIngredient item;
  final DateTime today;

  /// opens the correction dialog, for fixing a receiving mistake
  final VoidCallback onCorrect;
  final bool depleted;

  /// set in the grouped view, the ingredient name is already on the header
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final band = ExpiryRisk.bandFor(item.batch.expiryDate, today);
    final colour = depleted ? AppColors.inkDisabled : bandColour(band);
    final textColour = depleted ? AppColors.inkDisabled : AppColors.inkBody;
    final unit = item.unitOfMeasure;

    return Container(
      padding: EdgeInsets.fromLTRB(
        indented ? AppSpacing.xxl : AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.statusBarWidth,
            height: 36,
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // the ingredient name only when the header isn't carrying it
                    if (!indented)
                      Text(
                        item.ingredientName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: textColour),
                      ),
                    if (!indented) const SizedBox(width: AppSpacing.sm),
                    Text(
                      ExpiryRisk.describe(item.batch.expiryDate, today),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: indented ? FontWeight.w600 : null,
                        color: depleted ? AppColors.inkDisabled : colour,
                      ),
                    ),
                    // the till refuses to sell this, so say so where the
                    // manager is deciding what to throw out
                    if (!depleted &&
                        ExpiryRisk.isExpired(item.batch.expiryDate, today)) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '· cannot be sold',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colour,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '${item.batch.expiryDate} · '
                  '${quantity(item.batch.containerCapacity)} $unit containers · '
                  '${item.batch.containersReceived} received · '
                  // the real batch id, the same one the void dialog, the closing
                  // count and the csv exports all refer to
                  'batch #${item.batch.batchId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // a corrected batch is worth seeing without opening anything,
                // it's the only place the correction is recorded
                if (item.batch.wasCorrected)
                  Text(
                    'Corrected by ${item.correctedByName ?? 'a manager'} on '
                    '${item.batch.correctedAt!.substring(0, 10)}'
                    '${item.batch.correctionChangedQuantity ? ' · was ${quantity(item.batch.previousQuantity!)} $unit' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.info,
                        ),
                  ),
              ],
            ),
          ),
          Text(
            depleted
                ? 'empty'
                : '${quantity(item.batch.quantityRemaining)} $unit',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: textColour),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Correct these figures',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onCorrect,
          ),
        ],
      ),
    );
  }
}

/// the band colours, from the semantic palette so nothing invents its own red
Color bandColour(ExpiryBand band) {
  switch (band) {
    case ExpiryBand.red:
      return AppColors.danger;
    case ExpiryBand.yellow:
      return AppColors.caution;
    case ExpiryBand.green:
      return AppColors.safe;
  }
}

/// the same band as readable text, amber has to darken or it disappears
Color bandTextColour(ExpiryBand band) {
  switch (band) {
    case ExpiryBand.red:
      return AppColors.dangerText;
    case ExpiryBand.yellow:
      return AppColors.cautionText;
    case ExpiryBand.green:
      return AppColors.safeText;
  }
}
