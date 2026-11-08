import '../data/stock_item.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import 'daily_report.dart';

// the sentences and cells the report and the template summary share, so both always say the same thing
// every amount is in base units with the word the barista knows, like "500 ml" or "6 packs"
// owner wording: "orders", never "tally" (the barista side keeps "Tally")

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

// number items whose gap isnt 0, the ones the summary and the email point out
// container items never have a daily gap so they are never in here (rule 7)
List<UsageRow> gapRows(DailyReport report) => [
  for (final row in report.compared)
    if (row.gap != null && gapCell(row.item, row.gap!) != '0') row,
];

// gapRows with the most important first: the biggest gap compared to what the orders explain
// a percent and not the plain size, since 20 g of beans and 2 wings cant be compared
// an item the orders explain none of (expected 0) but that was used goes first
List<UsageRow> rankedGapRows(DailyReport report) {
  double weight(UsageRow row) {
    final expected = row.expected!;
    if (expected <= 0) return double.infinity;
    return row.gap!.abs() / expected;
  }

  return gapRows(report)..sort((a, b) => weight(b).compareTo(weight(a)));
}

// number items that matched today's orders exactly
List<UsageRow> matchedRows(DailyReport report) => [
  for (final row in report.compared)
    if (row.gap != null && gapCell(row.item, row.gap!) == '0') row,
];

// the used cell of a number item, an opening count has no usage yet (rule 7)
String usedCell(UsageRow row) {
  if (row.isOpening) return openingText;
  return amountText(row.item, row.actual!);
}

// a gap in words, item name first, with the item's note if there is one
// like "Fries pack: based on today's orders, 2 packs should have been used, 3 packs were used (1 pack more).
// Staff noted “1 dropped”, which may explain part of it."
// a note never counts as the cause, and with no note it says so instead of guessing
String gapSentence(UsageRow row) {
  final item = row.item;
  final gap = row.gap!;
  final way = gap > 0 ? 'more' : 'less';
  final numbers =
      '${item.name}: based on today\'s orders, '
      '${amountText(item, row.expected!)} should have been used, '
      '${amountText(item, row.actual!)} ${row.actual == 1 ? 'was' : 'were'} used '
      '(${amountText(item, gap.abs())} $way).';
  return '$numbers ${noteSentence(row.line.note)}';
}

// how a note is linked to a number, careful words only and no new numbers
String noteSentence(String? note) {
  if (note == null || note.isEmpty) return 'No note explains it.';
  return 'Staff noted “$note”, which may explain part of it.';
}

// a container check in words (rule 7), what it held vs what the orders explain, no judging
// like "Caramel syrup: 1 bottle (2,000 ml) finished. Based on orders since Oct 28, 1,700 ml should have been used."
// the window goes back to the last finished container, so it says "since" when that was an earlier day
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
      ? "today's orders"
      : 'orders since ${formatShortDate(check.sinceDate)}';
  return '$finished Based on $since, ${amountText(item, expected)} '
      'should have been used.';
}

// what is left at End, about when it came from a level (rule 2)
// container items show containers like the logbook, number items like "4 packs"
String endText(UsageRow row) {
  final item = row.item;
  final end = row.line.endQty;
  final amount = item.countType == CountType.container
      ? formatContainers(end / item.containerSize!, item.containerName)
      : amountText(item, end);
  return row.line.endIsExact ? amount : 'about $amount';
}

// a restock item in words, like "Fries pack: 5 packs left (low level 5 packs)."
String restockSentence(UsageRow row) =>
    '${row.item.name}: ${endText(row)} left (low level ${row.item.lowText}).';

// the date line, like "Fri, Oct 30" or "Fri, Oct 30 (covers Oct 29–30)"
String reportDate(DailyReport report) {
  final day = report.day;
  final date = formatLongDate(day.businessDate);
  final from = day.coversFrom;
  if (from == null) return date;
  return '$date (covers ${formatCovers(from, day.businessDate)})';
}
