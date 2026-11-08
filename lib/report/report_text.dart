import '../data/stock_item.dart';
import '../logic/formatting.dart';
import 'daily_report.dart';

// the sentences and cells the report and the template summary share, so both always say the same thing
// every amount is in base units with the word the barista knows, like "500 ml" or "6 packs"

// what the report says on an opening count instead of numbers (rule 7)
const String openingText = 'Opening count: comparing starts next count.';

// a gap smaller than this counts as 0, decimal math leaves tiny leftovers like 0.0000001
const double _zero = 0.005;

// the gap cell, like "+1 pack", "−20 g" or "0"
String gapCell(StockItem item, double gap) {
  if (gap.abs() < _zero) return '0';
  final sign = gap > 0 ? '+' : '−';
  return '$sign${amountText(item, gap.abs())}';
}

// the used cell, an estimate always says about (rule 7)
String usedCell(UsageRow row) {
  if (row.isOpening) return openingText;
  final actual = amountText(row.item, row.actual!);
  return row.actualIsExact ? actual : 'about $actual (estimated)';
}

// a gap in words, like "Fries pack: 1 pack more used than the tally explains."
String gapSentence(UsageRow row) {
  final gap = row.gap!;
  final name = row.item.name;
  if (gap.abs() < _zero) return '$name: matched the recipes.';
  final amount = amountText(row.item, gap.abs());
  final way = gap > 0 ? 'more' : 'less';
  return '$name: $amount $way used than the tally explains.';
}

// an estimated item side by side with its expected, no gap (rule 7)
// like "Caramel syrup: about 500 ml used (estimated from bottle level). Recipes expect 420 ml."
String estimatedSentence(UsageRow row) {
  final item = row.item;
  final used = amountText(item, row.actual!);
  final expected = amountText(item, row.expected!);
  return '${item.name}: about $used used (estimated from '
      '${item.containerName} level). Recipes expect $expected.';
}

// a container check in words (rule 7)
// like "Caramel syrup: 1 bottle (2,000 ml) finished. Recipes explain 1,700 ml since Oct 28."
String checkSentence(CheckRow check, String today) {
  final item = check.item;
  final containers = formatContainers(
    check.containers.toDouble(),
    item.containerName,
  );
  final total = amountText(item, check.containerTotal);
  final finished = '${item.name}: $containers ($total) finished.';

  final expected = check.expectedSinceLast;
  if (expected == null) return '$finished No recipe uses it.';
  final since = check.sinceDate == today
      ? 'today'
      : 'since ${formatShortDate(check.sinceDate)}';
  return '$finished Recipes explain ${amountText(item, expected)} $since.';
}

// the date line, like "Fri, Oct 30" or "Fri, Oct 30 (covers Oct 29–30)"
String reportDate(DailyReport report) {
  final day = report.day;
  final date = formatLongDate(day.businessDate);
  final from = day.coversFrom;
  if (from == null) return date;
  return '$date (covers ${formatCovers(from, day.businessDate)})';
}
