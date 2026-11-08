import '../data/count_line.dart';
import '../data/stock_item.dart';
import '../data/tally_store.dart';

// one stock item's numbers of a submitted day, from day_results + its count line (rule 7)
class UsageRow {
  const UsageRow({
    required this.item,
    required this.line,
    required this.expected,
    required this.actual,
    required this.actualIsExact,
    required this.gap,
    required this.restock,
  });

  final StockItem item;
  final CountLine line;
  // what the recipes explain, null when the item is in no recipe
  final double? expected;
  // start + in - end, null on an opening count
  final double? actual;
  // false when Start or End came from a level button, then there is no gap
  final bool actualIsExact;
  // actual - expected, only when both are there and the actual is exact
  final double? gap;
  // End is at or below the low-stock level (rule 8)
  final bool restock;

  bool get isOpening => line.isOpening;
  // in at least 1 recipe, so it goes in the expected vs actual table
  bool get hasRecipe => expected != null;
}

// a container check of the day, same as a container_checks row (rule 7)
class CheckRow {
  const CheckRow({
    required this.item,
    required this.containers,
    required this.containerTotal,
    required this.expectedSinceLast,
    required this.sinceDate,
  });

  final StockItem item;
  final int containers;
  // what was really used up, in base units
  final double containerTotal;
  // what the recipes explain since the last finished container, null = in no recipe
  final double? expectedSinceLast;
  final String sinceDate;
}

// everything the owner's daily report needs, read from what submit saved
// every number here is worked out by the app, the summary (template or ai) only puts them into words
class DailyReport {
  const DailyReport({
    required this.day,
    required this.closedDates,
    required this.usage,
    required this.checks,
    required this.noRecipe,
    required this.tally,
  });

  final BusinessDay day;
  // skipped days the barista said were closed, right before this day (rule 5)
  final List<String> closedDates;
  // every counted item, by category then name
  final List<UsageRow> usage;
  final List<CheckRow> checks;
  // tallied menu item names with no recipe at submit (and not "no recipe needed")
  final List<String> noRecipe;
  // menu item + quantity, only lines above 0
  final List<TallyRow> tally;

  List<UsageRow> get restock => [
    for (final row in usage)
      if (row.restock) row,
  ];

  // the expected vs actual table: items in a recipe
  List<UsageRow> get compared => [
    for (final row in usage)
      if (row.hasRecipe) row,
  ];

  // the full count table, same rows as history
  List<CountRow> get countRows => [
    for (final row in usage) CountRow(line: row.line, item: row.item),
  ];

  // how many menu items were made in all, a count not money
  int get madeTotal => tally.fold(0, (sum, row) => sum + row.qty);
}
