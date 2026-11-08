import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../logic/formatting.dart';
import '../../theme/app_theme.dart';

// 1 point on the chart: a day or a week
class ChartPoint {
  const ChartPoint({
    required this.label,
    required this.used,
    required this.expected,
  });

  // what shows under the point, like "Nov 2"
  final String label;
  final double used;
  // null = no recipe that day, the expected line has a hole there
  final double? expected;
}

// most labels under the chart, more would overlap, the rest are skipped
const int _maxLabels = 10;

// the analytics line chart: used (brown, solid) vs expected from orders (caramel, dashed)
// fl_chart draws it, x = the place of the point (0, 1, 2...), y = the amount in the item's unit
class UsageChart extends StatelessWidget {
  const UsageChart({super.key, required this.points, required this.unit});

  final List<ChartPoint> points;
  // the item's unit word, like "packs", for the touch popup
  final String unit;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    // show every step-th label so they dont overlap on a long range
    final step = math.max(1, (points.length / _maxLabels).ceil());

    return LineChart(
      LineChartData(
        minY: 0,
        // half a step of room on both sides so the first and last dots arent cut in half
        minX: -0.5,
        maxX: points.length - 0.5,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].used),
            ],
            color: AppColors.espresso,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                // nullSpot = a hole in the line, a day with no recipe has no expected
                points[i].expected == null
                    ? FlSpot.nullSpot
                    : FlSpot(i.toDouble(), points[i].expected!),
            ],
            color: AppColors.caramel,
            barWidth: 2,
            // 6 px line, 4 px gap = dashed
            dashArray: const [6, 4],
            dotData: const FlDotData(show: true),
          ),
        ],
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
              reservedSize: 44,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(formatAmount(value), style: small),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                // only whole places that are a point, and only every step-th one
                if (value != i ||
                    i < 0 ||
                    i >= points.length ||
                    i % step != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(points[i].label, style: small),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        // the popup when a point is touched, like "Used 3 packs"
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${spot.barIndex == 0 ? 'Used' : 'Expected'} '
                  '${formatAmount(spot.y)} $unit',
                  const TextStyle(color: Colors.white, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
