import 'package:flutter/material.dart';

import '../../data/analytics_store.dart';
import '../../logic/analytics_math.dart';
import '../../logic/formatting.dart';
import '../../report/report_text.dart';
import '../../theme/app_theme.dart';
import 'usage_chart.dart';

// the chosen dates: the last this many days, ending at the newest submitted day
const List<int> rangeDays = [7, 30, 90];

// the owner's analytics tab (feature 10)
// left: a chart of used vs expected (from orders) for 1 number item, by day or by week,
// and under it a plain table of every number item: days counted, days with a gap, total gap
// right: every container finished, and menu items ordered with no recipe yet
// no thresholds, no filtering, no highlighting: the owner judges (rule 7)
// owner wording: "orders", never "tally"
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key, required this.store});

  final AnalyticsStore store;

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  // width of the right column
  static const double _sideWidth = 340;
  // height of the chart
  static const double _chartHeight = 280;

  // how many days back, one of rangeDays
  int _days = rangeDays.first;
  // false = by day (the default), true = by week
  bool _byWeek = false;
  // the item on the chart, null = the first one
  int? _itemId;

  // the newest submitted date, null before the first submit
  String? _lastDate;
  // null while loading
  Analytics? _data;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // the first day of the chosen dates, both days are included so 7 days = to minus 6
  String _fromDate(String to) {
    final end = DateTime.parse(to);
    final start = end.subtract(Duration(days: _days - 1));
    return start.toIso8601String().substring(0, 10);
  }

  Future<void> _load() async {
    final last = await widget.store.lastSubmittedDate();
    final data = last == null
        ? null
        : await widget.store.load(_fromDate(last), last);
    if (!mounted) return;
    setState(() {
      _lastDate = last;
      _data = data;
      _loaded = true;
      // keep the picked item if it is still in these dates
      final ids = <int?>[
        for (final item in data?.numberItems ?? const []) item.id,
      ];
      if (!ids.contains(_itemId)) _itemId = ids.isEmpty ? null : ids.first;
    });
  }

  void _pickDays(int days) {
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Card(child: Center(child: CircularProgressIndicator()));
    }
    final data = _data;
    final last = _lastDate;
    if (data == null || last == null) return _empty(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, last),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _chartCard(context, data),
                    const SizedBox(height: 12),
                    _gapTable(context, data),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _sideWidth,
                child: ListView(
                  children: [
                    _checksCard(context, data),
                    const SizedBox(height: 12),
                    _noRecipeCard(context, data),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // shown before the first submit
  Widget _empty(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insights_outlined,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 10),
            Text('No submitted days yet', style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Analytics show here after Submit.', style: text.bodySmall),
          ],
        ),
      ),
    );
  }

  // title, the dates, and the 2 toggles
  Widget _header(BuildContext context, String last) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // title on the left, the 2 toggles pushed to the right
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Analytics', style: text.titleLarge),
                Text(
                  '${formatShortDate(_fromDate(last))} – ${formatShortDate(last)}',
                  style: text.bodySmall,
                ),
              ],
            ),
            const SizedBox(width: 16),
            // Expanded + Wrap end = the toggles sit on the right, and go to a 2nd line if they dont fit
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 16,
                runSpacing: 8,
                children: [
                  SegmentedButton<int>(
                    key: const Key('analytics_range'),
                    segments: [
                      for (final days in rangeDays)
                        ButtonSegment(
                          value: days,
                          label: Text('Last $days days'),
                        ),
                    ],
                    selected: {_days},
                    showSelectedIcon: false,
                    onSelectionChanged: (picked) => _pickDays(picked.first),
                  ),
                  SegmentedButton<bool>(
                    key: const Key('analytics_view'),
                    segments: const [
                      ButtonSegment(value: false, label: Text('By day')),
                      ButtonSegment(value: true, label: Text('By week')),
                    ],
                    selected: {_byWeek},
                    showSelectedIcon: false,
                    onSelectionChanged: (picked) =>
                        setState(() => _byWeek = picked.first),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(BuildContext context, Analytics data) {
    final text = Theme.of(context).textTheme;
    final items = data.numberItems;
    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No items counted in pieces in these dates. Container items are '
            'compared when a container is finished, see Container checks.',
            style: text.bodyMedium,
          ),
        ),
      );
    }

    final item = items.firstWhere((item) => item.id == _itemId);
    final days = data.daysByItem[item.id]!;
    final points = _byWeek
        ? [
            for (final week in groupByWeek(days))
              ChartPoint(
                label: 'Wk ${formatShortDate(week.weekStart)}',
                used: week.used,
                expected: week.expected,
              ),
          ]
        : [
            for (final day in days)
              ChartPoint(
                label: formatShortDate(day.date),
                used: day.used,
                expected: day.expected,
              ),
          ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Expanded = the title takes what is left and wraps, the item picker keeps its size
                Expanded(
                  child: Text(
                    'Used vs. expected (from orders)',
                    style: text.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  key: const Key('analytics_item'),
                  value: item.id,
                  items: [
                    for (final option in items)
                      DropdownMenuItem(
                        value: option.id,
                        child: Text(option.name),
                      ),
                  ],
                  onChanged: (id) => setState(() => _itemId = id),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Wrap = goes to a 2nd line when the card is narrow instead of running off the side
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _legend(AppColors.espresso, 'Used'),
                _legend(AppColors.caramel, 'Expected (from orders)'),
                Text('in ${item.unitWord}', style: text.bodySmall),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _chartHeight,
              child: UsageChart(points: points, unit: item.unitWord),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 4, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  // every number item in these dates, sorted by total gap, no filtering or highlighting
  Widget _gapTable(BuildContext context, Analytics data) {
    final text = Theme.of(context).textTheme;
    if (data.numberItems.isEmpty) return const SizedBox.shrink();
    final items = {for (final item in data.numberItems) item.id!: item};
    final rows = summarizeGaps(data.daysByItem);

    Widget cell(String value, {bool header = false, bool right = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          value,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: header ? text.bodySmall : text.bodyMedium,
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gaps by item', style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Items counted in pieces. Gap = used − expected (from orders), '
              '+ means more was used than the orders explain.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 8),
            Table(
              key: const Key('gap_table'),
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              border: const TableBorder(
                horizontalInside: BorderSide(color: AppColors.divider),
              ),
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: AppColors.cream),
                  children: [
                    cell('Item', header: true),
                    cell('Days counted', header: true, right: true),
                    cell('Days with a gap', header: true, right: true),
                    cell('Total gap', header: true, right: true),
                  ],
                ),
                for (final row in rows)
                  TableRow(
                    children: [
                      cell(items[row.stockItemId]!.name),
                      cell('${row.daysCounted}', right: true),
                      cell('${row.daysWithGap}', right: true),
                      cell(
                        gapCell(items[row.stockItemId]!, row.totalGap),
                        right: true,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // every container finished in these dates, held vs what the orders explain, no judging
  Widget _checksCard(BuildContext context, Analytics data) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Container checks', style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Each finished container: what it held vs. what the orders '
              'since the last one explain.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 8),
            if (data.checks.isEmpty)
              Text(
                'No container finished in these dates.',
                style: text.bodyMedium,
              )
            else
              for (final entry in data.checks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatLongDate(entry.date), style: text.bodySmall),
                      Text(
                        checkSentence(entry.check, entry.date),
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _noRecipeCard(BuildContext context, Analytics data) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('No recipe yet', style: text.titleMedium),
            const SizedBox(height: 2),
            Text(
              'Ordered but not compared. Add a recipe in Menu & Recipes.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 8),
            if (data.noRecipe.isEmpty)
              Text('Every ordered item had a recipe.', style: text.bodyMedium)
            else
              for (final entry in data.noRecipe)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${entry.name}: ordered on ${entry.days} '
                    '${entry.days == 1 ? 'day' : 'days'}',
                    style: text.bodyMedium,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
