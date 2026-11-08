import '../logic/formatting.dart';
import 'daily_report.dart';
import 'report_text.dart';
import 'summary_parts.dart';

// the closing line when no number item has a gap
const String allMatchedText = 'Everything else matched.';

// the fill-in-the-blanks summary, built only from the app's own numbers (rule 10)
// used when there is no ai summary: no internet, the call failed, or the ai answer didnt pass the checks
// same 5 parts as the ai one so a fallback email reads the same way
// a part is left empty when it has nothing to say, the email hides it
// no thresholds: every gap that isnt 0 and every finished container is listed, the owner judges
SummaryParts templateSummary(DailyReport report) {
  final day = report.day;
  final today = day.businessDate;

  // today: orders, then anything about the day itself
  final overview = <String>[];
  final made = report.madeTotal;
  overview.add(
    made == 0
        ? 'No orders were recorded today.'
        : '$made ${made == 1 ? 'menu item was' : 'menu items were'} ordered today.',
  );
  if (report.noRecipe.isNotEmpty) {
    overview.add(
      'Ordered with no recipe yet, so not compared: '
      '${report.noRecipe.join(', ')}.',
    );
  }
  final from = day.coversFrom;
  if (from != null) {
    overview.add('This count covers ${formatCovers(from, today)}.');
  }
  if (report.closedDates.isNotEmpty) {
    overview.add(
      'Closed: ${report.closedDates.map(formatShortDate).join(', ')}.',
    );
  }
  final opening = [
    for (final row in report.usage)
      if (row.isOpening) row.item.name,
  ];
  if (opening.isNotEmpty) {
    overview.add(
      'Opening count for ${opening.join(', ')}, comparing starts next count.',
    );
  }
  if (day.dayNote != null) overview.add('Day note: “${day.dayNote}”.');

  final gaps = rankedGapRows(report);

  return SummaryParts(
    overview: overview.join(' '),
    // every number item whose gap isnt 0, biggest first, each with its note
    gaps: [for (final row in gaps) gapSentence(row)].join(' '),
    restock: [for (final row in report.restock) restockSentence(row)].join(' '),
    // every finished container, what it held vs what the orders explain
    containers: [
      for (final check in report.checks) checkSentence(check, today),
    ].join(' '),
    // only true when something was compared and nothing had a gap
    fine: gaps.isEmpty && report.compared.any((row) => row.gap != null)
        ? allMatchedText
        : '',
  );
}
