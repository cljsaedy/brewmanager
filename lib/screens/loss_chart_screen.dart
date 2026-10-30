import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../database/ingredient_repository.dart';
import '../database/loss_analytics_repository.dart';
import '../logic/formatting.dart';
import '../logic/loss_aggregator.dart';
import '../models/ingredient.dart';
import '../models/loss_record.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';

/// the material loss chart, declared losses against unexplained drift
///
/// this is the only chart in scope, gross sales is deliberately excluded, the
/// study is about material loss not revenue
class LossChartScreen extends StatefulWidget {
  const LossChartScreen({super.key});

  @override
  State<LossChartScreen> createState() => _LossChartScreenState();
}

/// the date range choices
enum _Range {
  week('Last 7 days', 7),
  month('Last 30 days', 30),
  quarter('Last 90 days', 90),
  all('All time', 3650);

  const _Range(this.label, this.days);

  final String label;
  final int days;
}

class _LossChartScreenState extends State<LossChartScreen> {
  final _losses = LossAnalyticsRepository();
  final _ingredients = IngredientRepository();

  List<Ingredient> _ingredientChoices = [];
  List<LossRecord> _records = [];

  _Range _range = _Range.month;
  // null means all ingredients
  int? _ingredientId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
    _reload();
  }

  Future<void> _loadIngredients() async {
    final list = await _ingredients.getActive();
    if (!mounted) return;
    setState(() => _ingredientChoices = list);
  }

  Future<void> _reload() async {
    setState(() => _loading = true);

    final now = DateTime.now();
    final records = await _losses.getLosses(
      from: now.subtract(Duration(days: _range.days)),
      to: now,
      ingredientId: _ingredientId,
    );

    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  /// one bar per day when a single ingredient is picked, otherwise one per ingredient
  ///
  /// a single ingredient means one unit, so a day by day view adds up honestly
  List<LossBar> get _bars => _ingredientId == null
      ? LossAggregator.byIngredient(_records)
      : LossAggregator.byDay(_records);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Material Loss'),
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
          _buildFilters(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                ? const EmptyState(
                    icon: Icons.bar_chart,
                    title: 'No losses in this period',
                    message:
                        'Declared losses and shortfalls found by the '
                        'closing count will appear here.',
                  )
                // one ingredient means one unit, so a day by day chart is
                // honest there and a trend is what is wanted once the
                // ingredient to look at is already known
                : _ingredientId != null
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: _LossBarChart(bars: _bars),
                  )
                : _buildRankedLists(),
          ),
        ],
      ),
    );
  }

  /// across all ingredients, two ranked lists rather than one stacked chart
  ///
  /// stacking the two categories together made unexplained loss impossible to
  /// compare between ingredients, which is the comparison that leads to doing
  /// something, and the chart's axis was in containers while the figures beside
  /// it were in millilitres and grams, so the same fact appeared twice in
  /// units that could not be reconciled
  Widget _buildRankedLists() {
    final unexplained = LossAggregator.ranked(
      records: _records,
      category: LossCategory.unexplained,
      ingredients: _ingredientChoices,
    );
    final reported = LossAggregator.ranked(
      records: _records,
      category: LossCategory.declared,
      ingredients: _ingredientChoices,
    );

    // one scale for both lists, so a bar of a given length means the same
    // amount of stock whichever list it is in
    final largest = [
      LossAggregator.largestContainers(unexplained),
      LossAggregator.largestContainers(reported),
    ].reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        _NeedsAttentionCard(
          worst: LossAggregator.needsAttention(
            records: _records,
            ingredients: _ingredientChoices,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _RankedList(
                  title: 'Unexplained loss',
                  explanation:
                      'Stock the closing count could not find, with no '
                      'reported cause. Usually over-pouring, drinks given '
                      'away, or a recipe that does not match what staff '
                      'actually make.',
                  rows: unexplained,
                  colour: AppColors.unexplainedLoss,
                  largest: largest,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _RankedList(
                  title: 'Declared loss',
                  explanation:
                      'Containers staff declared as lost at the time — '
                      'dropped, spilled or spoiled. Usually points at '
                      'handling or storage rather than at how drinks are '
                      'made.',
                  rows: reported,
                  colour: AppColors.declaredLoss,
                  largest: largest,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          DropdownButton<_Range>(
            value: _range,
            underline: const SizedBox.shrink(),
            items: [
              for (final r in _Range.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _range = v);
              _reload();
            },
          ),
          const SizedBox(width: AppSpacing.xl),
          DropdownButton<int?>(
            value: _ingredientId,
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All ingredients'),
              ),
              for (final i in _ingredientChoices)
                DropdownMenuItem(value: i.ingredientId, child: Text(i.name)),
            ],
            onChanged: (v) {
              setState(() => _ingredientId = v);
              _reload();
            },
          ),
          const Spacer(),
          // only needed for the single ingredient chart, where the two
          // categories are stacked in one bar
          //
          // the ranked lists carry a swatch in each heading instead, so a
          // legend there would just repeat itself
          if (_ingredientId != null) ...[
            const _LegendDot(
              color: AppColors.declaredLoss,
              label: 'Declared loss',
            ),
            const SizedBox(width: AppSpacing.lg),
            const _LegendDot(
              color: AppColors.unexplainedLoss,
              label: 'Unexplained',
            ),
          ],
        ],
      ),
    );
  }
}

/// stacked bars, declared at the bottom and unexplained on top
class _LossBarChart extends StatelessWidget {
  const _LossBarChart({required this.bars});

  final List<LossBar> bars;

  @override
  Widget build(BuildContext context) {
    final unit = bars.isEmpty ? '' : bars.first.unit;
    final maxTotal = bars.fold<double>(0, (m, b) => b.total > m ? b.total : m);
    final mixed = unit == LossAggregator.mixedUnit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mixed
              // units differ between ingredients, so the axis has to be unit free
              ? 'Loss in containers'
              : 'Loss in $unit',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (mixed)
          Text(
            'Ingredients are measured differently, so this is shown as whole '
            'containers to compare them fairly.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: BarChart(
            BarChartData(
              // a little headroom so the tallest bar isn't flush with the top
              maxY: maxTotal * 1.15,
              barGroups: [
                for (var i = 0; i < bars.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: bars[i].total,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                        // stacked, each segment ends where the next begins
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            bars[i].declared,
                            AppColors.declaredLoss,
                          ),
                          BarChartRodStackItem(
                            bars[i].declared,
                            bars[i].total,
                            AppColors.unexplainedLoss,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
              // faint horizontal lines only, a full grid competes with the bars
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: _niceInterval(maxTotal),
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: AppColors.hairline, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    // an explicit round interval, left to itself the chart
                    // divides the range and labels the gridlines 3.036 and such
                    interval: _niceInterval(maxTotal),
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Text(
                        quantity(value),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= bars.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          bars[index].label,
                          style: const TextStyle(fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.ink,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final bar = bars[group.x];
                    return BarTooltipItem(
                      '${bar.label}\n'
                      'Declared ${quantity(bar.declared)}\n'
                      'Unexplained ${quantity(bar.unexplained)}',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// a round step for the gridlines, roughly four lines up the chart
///
/// picks 1, 2, 5 or 10 scaled to the size of the numbers, so an axis reading in
/// containers steps 0 1 2 3 and one reading in millilitres steps 0 500 1000
double _niceInterval(double maxValue) {
  if (maxValue <= 0) return 1;

  final rough = maxValue / 4;
  final magnitude = pow(10, (log(rough) / ln10).floor()).toDouble();
  final normalised = rough / magnitude;

  final double step;
  if (normalised <= 1) {
    step = 1;
  } else if (normalised <= 2) {
    step = 2;
  } else if (normalised <= 5) {
    step = 5;
  } else {
    step = 10;
  }
  return step * magnitude;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// the ingredient with the worst unexplained loss, and why that matters
///
/// ranked on unexplained rather than total loss, because a reported loss is
/// already explained and points at an incident, while unexplained loss points
/// at something about the way the shop runs
class _NeedsAttentionCard extends StatelessWidget {
  const _NeedsAttentionCard({required this.worst});

  /// null when there is no unexplained loss at all in the period
  final LossRanking? worst;

  @override
  Widget build(BuildContext context) {
    final item = worst;

    if (item == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        color: AppColors.safe.withValues(alpha: 0.08),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.safe),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'No unexplained loss in this period. Everything that went '
                'missing was declared at the time.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: AppColors.danger.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.priority_high, color: AppColors.danger),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEEDS ATTENTION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${item.ingredientName} — '
                  '${quantity(item.quantity)} ${item.unitOfMeasure} '
                  'unexplained',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'That is about ${quantity(item.containers)} '
                  'container${item.containers == 1 ? '' : 's'} nobody can '
                  'account for. Worth checking how it is being poured and '
                  'whether the recipe matches what staff actually make.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// one category of loss, every ingredient ranked worst first
class _RankedList extends StatelessWidget {
  const _RankedList({
    required this.title,
    required this.explanation,
    required this.rows,
    required this.colour,
    required this.largest,
  });

  final String title;

  /// one plain sentence on what this category is and what it usually points to,
  /// because the two categories are the whole point of the screen and the
  /// colours alone never said which was which
  final String explanation;

  final List<LossRanking> rows;
  final Color colour;

  /// the biggest bar across both lists, so a bar length means the same thing
  /// wherever it appears
  final double largest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(explanation, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) =>
                _RankedRow(row: rows[index], colour: colour, largest: largest),
          ),
        ),
      ],
    );
  }
}

/// one ingredient's loss: the real amount to read, and a bar to compare
class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.row,
    required this.colour,
    required this.largest,
  });

  final LossRanking row;
  final Color colour;
  final double largest;

  @override
  Widget build(BuildContext context) {
    // a row with no loss stays visible but steps back, so an ingredient that
    // is fine reads as fine rather than as missing
    final dimmed = row.isZero;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.ingredientName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: dimmed ? AppColors.inkDisabled : AppColors.inkBody,
                  ),
                ),
              ),
              Text(
                // the real unit, which is what a manager acts on
                dimmed
                    ? 'none'
                    : '${quantity(row.quantity)} ${row.unitOfMeasure}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: dimmed ? AppColors.inkDisabled : AppColors.inkBody,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // the bar is the container equivalent, which is the only fair way to
          // compare a loss in millilitres against one in grams
          _LossBar(
            fraction: largest <= 0 ? 0 : row.containers / largest,
            colour: colour,
            dimmed: dimmed,
          ),
          if (!dimmed) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${quantity(row.containers)} '
              'container${row.containers == 1 ? '' : 's'} worth',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _LossBar extends StatelessWidget {
  const _LossBar({
    required this.fraction,
    required this.colour,
    required this.dimmed,
  });

  final double fraction;
  final Color colour;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 10,
        color: AppColors.hairline,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction.clamp(0.0, 1.0),
          child: Container(color: dimmed ? Colors.transparent : colour),
        ),
      ),
    );
  }
}
