import '../logic/formatting.dart';
import 'daily_report.dart';
import 'report_text.dart';

// most names a list in the summary shows, the rest is "and 3 more", the tables have them all
// keeps the summary short (about 120 words like the ai one, rule 10)
const int summaryListMax = 4;

// the fill-in-the-blanks summary, built only from the app's own numbers (rule 10)
// used when there is no ai summary: no internet, the call failed, or the ai numbers didnt match
// gives back bullet points, 1 point each, the email shows them as a list
// a bullet is left out when it has nothing to say
// the date is not in here since the email header already shows it
List<String> templateSummary(DailyReport report) {
  final bullets = <String>[];

  final made = report.madeTotal;
  bullets.add(
    made == 0
        ? 'Nothing was tallied.'
        : '$made ${made == 1 ? 'menu item was' : 'menu items were'} tallied.',
  );

  final restock = report.restock;
  bullets.add(
    restock.isEmpty
        ? 'No items need restocking.'
        : 'Restock recommended: '
              '${_list([for (final row in restock) row.item.name])}.',
  );

  // exact items with a gap that isnt 0, the ones that matched are only in the table
  final gaps = gapRows(report);
  final exactCompared = [
    for (final row in report.compared)
      if (row.gap != null) row,
  ];
  if (gaps.isNotEmpty) {
    bullets.addAll([
      for (final row in gaps.take(summaryListMax)) gapSentence(row),
    ]);
    if (gaps.length > summaryListMax) {
      bullets.add(
        '${gaps.length - summaryListMax} more gaps are in the table.',
      );
    }
  } else if (exactCompared.isNotEmpty) {
    bullets.add('Every exact item matched the recipes.');
  }

  final checks = report.checks;
  bullets.addAll([
    for (final check in checks.take(summaryListMax))
      checkSentence(check, report.day.businessDate),
  ]);
  if (checks.length > summaryListMax) {
    bullets.add(
      '${checks.length - summaryListMax} more container checks are in the report.',
    );
  }

  if (report.noRecipe.isNotEmpty) {
    bullets.add('No recipe yet: ${_list(report.noRecipe)}.');
  }

  final opening = [
    for (final row in report.usage)
      if (row.isOpening) row.item.name,
  ];
  if (opening.isNotEmpty) {
    bullets.add(
      'Opening count for ${_list(opening)}, comparing starts next count.',
    );
  }

  final from = report.day.coversFrom;
  if (from != null) {
    bullets.add(
      'This count covers ${formatCovers(from, report.day.businessDate)}.',
    );
  }

  if (report.closedDates.isNotEmpty) {
    bullets.add(
      'Closed: ${_list([for (final date in report.closedDates) formatShortDate(date)])}.',
    );
  }

  if (report.day.dayNote != null) {
    bullets.add('Day note: “${report.day.dayNote}”.');
  }

  return bullets;
}

// turns the ai text into bullet points (rule 10)
// the ai is told to start every point with "- ", but this takes "* " and "• " too
// any line without a mark still becomes its own bullet, so a plain paragraph is 1 bullet and nothing is lost
// ** (markdown bold) is taken out since the email would show the stars as text
List<String> summaryBullets(String text) {
  final bullets = <String>[];
  for (final rawLine in text.split('\n')) {
    var line = rawLine.trim().replaceAll('**', '');
    if (line.startsWith('- ') ||
        line.startsWith('* ') ||
        line.startsWith('• ')) {
      line = line.substring(2).trim();
    }
    if (line.isNotEmpty) bullets.add(line);
  }
  return bullets;
}

// like "Milk, Cups, Beans and 2 more"
String _list(List<String> names) {
  if (names.length <= summaryListMax) return names.join(', ');
  final shown = names.take(summaryListMax).join(', ');
  return '$shown and ${names.length - summaryListMax} more';
}
