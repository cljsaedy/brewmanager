import '../logic/formatting.dart';
import 'daily_report.dart';
import 'report_text.dart';

// most names a list in the summary shows, the rest is "and 3 more", the tables have them all
// keeps the summary short (about 120 words like the ai one, rule 10)
const int summaryListMax = 4;

// the fill-in-the-blanks summary, built only from the app's own numbers (rule 10)
// used when there is no ai summary: no internet, the call failed, or the ai numbers didnt match
// every sentence is left out when it has nothing to say
String templateSummary(DailyReport report) {
  final parts = <String>['Daily count for ${reportDate(report)}.'];

  final made = report.madeTotal;
  parts.add(
    made == 0
        ? 'Nothing was tallied.'
        : '$made ${made == 1 ? 'menu item was' : 'menu items were'} tallied.',
  );

  final restock = report.restock;
  parts.add(
    restock.isEmpty
        ? 'No items need restocking.'
        : 'Restock recommended: '
              '${_list([for (final row in restock) row.item.name])}.',
  );

  // exact items with a gap that isnt 0, the ones that matched are only in the table
  final compared = report.compared;
  final gaps = [
    for (final row in compared)
      if (row.gap != null && gapCell(row.item, row.gap!) != '0') row,
  ];
  final exactCompared = [
    for (final row in compared)
      if (row.gap != null) row,
  ];
  if (gaps.isNotEmpty) {
    parts.addAll([
      for (final row in gaps.take(summaryListMax)) gapSentence(row),
    ]);
    if (gaps.length > summaryListMax) {
      parts.add('${gaps.length - summaryListMax} more gaps are in the table.');
    }
  } else if (exactCompared.isNotEmpty) {
    parts.add('Every exact item matched the recipes.');
  }

  final checks = report.checks;
  parts.addAll([
    for (final check in checks.take(summaryListMax))
      checkSentence(check, report.day.businessDate),
  ]);
  if (checks.length > summaryListMax) {
    parts.add(
      '${checks.length - summaryListMax} more container checks are in the report.',
    );
  }

  if (report.noRecipe.isNotEmpty) {
    parts.add('No recipe yet: ${_list(report.noRecipe)}.');
  }

  final opening = [
    for (final row in report.usage)
      if (row.isOpening) row.item.name,
  ];
  if (opening.isNotEmpty) {
    parts.add(
      'Opening count for ${_list(opening)}, comparing starts next count.',
    );
  }

  if (report.closedDates.isNotEmpty) {
    parts.add(
      'Closed: ${_list([for (final date in report.closedDates) formatShortDate(date)])}.',
    );
  }

  if (report.day.dayNote != null) {
    parts.add('Day note: “${report.day.dayNote}”.');
  }

  return parts.join(' ');
}

// like "Milk, Cups, Beans and 2 more"
String _list(List<String> names) {
  if (names.length <= summaryListMax) return names.join(', ');
  final shown = names.take(summaryListMax).join(', ');
  return '$shown and ${names.length - summaryListMax} more';
}
