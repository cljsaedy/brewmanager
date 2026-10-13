import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../database/ingredient_repository.dart';
import '../database/loss_analytics_repository.dart';
import '../logic/loss_aggregator.dart';
import '../models/ingredient.dart';
import '../models/loss_record.dart';

/// the material loss chart, declared losses against unexplained drift
///
/// this is the only chart in scope, gross sales is deliberately excluded, the study
/// is about material loss not revenue
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
    final bars = _bars;
    final summary = LossAggregator.summary(_records);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Material Loss'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
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
                    ? const Center(
                        child: Text('No losses recorded in this period'),
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: _LossBarChart(bars: bars),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _SummaryTable(rows: summary),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          DropdownButton<_Range>(
            value: _range,
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
          const SizedBox(width: 24),
          DropdownButton<int?>(
            value: _ingredientId,
            items: [
              const DropdownMenuItem(value: null, child: Text('All ingredients')),
              for (final i in _ingredientChoices)
                DropdownMenuItem(value: i.ingredientId, child: Text(i.name)),
            ],
            onChanged: (v) {
              setState(() => _ingredientId = v);
              _reload();
            },
          ),
          const Spacer(),
          // the legend, the two categories the study keeps apart
          const _LegendDot(color: _declaredColour, label: 'Declared loss'),
          const SizedBox(width: 16),
          const _LegendDot(color: _unexplainedColour, label: 'Unexplained'),
        ],
      ),
    );
  }
}

const Color _declaredColour = Color(0xFF1565C0);
const Color _unexplainedColour = Color(0xFFC62828);

/// stacked bars, declared at the bottom and unexplained on top
class _LossBarChart extends StatelessWidget {
  const _LossBarChart({required this.bars});

  final List<LossBar> bars;

  @override
  Widget build(BuildContext context) {
    final unit = bars.isEmpty ? '' : bars.first.unit;
    final maxTotal =
        bars.fold<double>(0, (m, b) => b.total > m ? b.total : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          unit == LossAggregator.mixedUnit
              // units differ between ingredients, so the axis has to be unit free
              ? 'Loss in containers (ingredients use different units)'
              : 'Loss in $unit',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
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
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                        // stacked, each segment ends where the next begins
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            bars[i].declared,
                            _declaredColour,
                          ),
                          BarChartRodStackItem(
                            bars[i].declared,
                            bars[i].total,
                            _unexplainedColour,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 52),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= bars.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
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
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final bar = bars[group.x];
                    return BarTooltipItem(
                      '${bar.label}\n'
                      'Declared ${_fmt(bar.declared)}\n'
                      'Unexplained ${_fmt(bar.unexplained)}',
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

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

/// exact figures in each ingredient's real unit, whatever the chart's axis shows
class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.rows});

  final List<LossSummaryRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Exact figures',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              return ListTile(
                title: Text(row.ingredientName),
                subtitle: Text(
                  'Declared ${_fmt(row.declared)} ${row.unitOfMeasure}\n'
                  'Unexplained ${_fmt(row.unexplained)} ${row.unitOfMeasure}',
                ),
                isThreeLine: true,
                trailing: Text(
                  '${_fmt(row.total)} ${row.unitOfMeasure}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
