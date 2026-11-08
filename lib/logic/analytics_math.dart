import 'units.dart';

// the math of the owner's analytics tab (feature 10), no db and no screens here so it is easy to test
// only number items are here: container items have no daily gap, they show in container checks (rule 7)
// no thresholds anywhere: every gap counts, the owner judges

// a gap smaller than this counts as 0, decimal math leaves tiny leftovers like 0.0000001
const double _zero = 0.005;

// 1 number item on 1 submitted day, from day_results
class UsagePoint {
  const UsagePoint({
    required this.date,
    required this.used,
    required this.expected,
    required this.gap,
  });

  // YYYY-MM-DD
  final String date;
  // start + in - end
  final double used;
  // what the orders explain, null when the item was in no recipe that day
  final double? expected;
  // used - expected, null when there is no expected
  final double? gap;
}

// the days of 1 week added up, for "By week"
class WeekPoint {
  const WeekPoint({
    required this.weekStart,
    required this.used,
    required this.expected,
  });

  // the monday of that week, YYYY-MM-DD
  final String weekStart;
  final double used;
  // null when no day of that week had an expected
  final double? expected;
}

// the monday of the week a date is in, YYYY-MM-DD
// weekday: monday = 1 ... sunday = 7, so going back (weekday - 1) days lands on monday
String weekStartOf(String date) {
  final day = DateTime.utc(
    int.parse(date.substring(0, 4)),
    int.parse(date.substring(5, 7)),
    int.parse(date.substring(8, 10)),
  );
  final monday = day.subtract(Duration(days: day.weekday - 1));
  return monday.toIso8601String().substring(0, 10);
}

// adds the days up per week (monday to sunday), oldest week first
// expected only adds the days that had one, a week where none did stays null
List<WeekPoint> groupByWeek(List<UsagePoint> days) {
  final used = <String, double>{};
  final expected = <String, double>{};
  for (final day in days) {
    final week = weekStartOf(day.date);
    used[week] = (used[week] ?? 0) + day.used;
    final dayExpected = day.expected;
    if (dayExpected != null) {
      expected[week] = (expected[week] ?? 0) + dayExpected;
    }
  }
  final weeks = used.keys.toList()..sort();
  return [
    for (final week in weeks)
      WeekPoint(
        weekStart: week,
        used: roundAmount(used[week]!),
        expected: expected[week] == null ? null : roundAmount(expected[week]!),
      ),
  ];
}

// 1 row of the table under the chart: 1 number item over the chosen dates
class GapSummary {
  const GapSummary({
    required this.stockItemId,
    required this.daysCounted,
    required this.daysWithGap,
    required this.totalGap,
  });

  final int stockItemId;
  // days the item had a usage (an opening count has none so it isnt counted)
  final int daysCounted;
  // days whose gap wasnt 0
  final int daysWithGap;
  // every gap added up, + = more used than the orders explained over those days
  // a + day and a - day can cancel out, the days with a gap column still shows them
  final double totalGap;
}

// works out the table under the chart, sorted by total gap, biggest first
// every number item that was counted is in it, no filtering
// a tie keeps the order the items came in (by category then name)
List<GapSummary> summarizeGaps(Map<int, List<UsagePoint>> daysByItem) {
  final rows = [
    for (final entry in daysByItem.entries)
      GapSummary(
        stockItemId: entry.key,
        daysCounted: entry.value.length,
        daysWithGap: entry.value
            .where((day) => day.gap != null && day.gap!.abs() >= _zero)
            .length,
        totalGap: roundAmount(
          entry.value.fold(0.0, (sum, day) => sum + (day.gap ?? 0)),
        ),
      ),
  ];
  // List.sort isnt stable, so the place in the list breaks ties to keep the item order
  final order = {for (var i = 0; i < rows.length; i++) rows[i].stockItemId: i};
  rows.sort((a, b) {
    final byGap = b.totalGap.compareTo(a.totalGap);
    if (byGap != 0) return byGap;
    return order[a.stockItemId]!.compareTo(order[b.stockItemId]!);
  });
  return rows;
}
