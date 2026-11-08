import '../logic/formatting.dart';
import '../logic/units.dart';
import 'daily_report.dart';
import 'report_text.dart';
import 'template_summary.dart';

// the facts the ai gets (rule 10): every number already worked out by the app, plus the notes word for word
// never prices or anything personal, only stock items, menu item names, counts and notes
// numbers are rounded to 2 decimals the same way the report shows them, so the ai can copy them exactly
// the app decides what goes in each list and in what order, no thresholds: every gap and every finished container is in
// each gap's note sits next to its own numbers so the ai links the right note to the right item
// owner wording only, the word "tally" is never in here
Map<String, Object?> reportFacts(DailyReport report) {
  final day = report.day;
  final from = day.coversFrom;

  return {
    'date': formatLongDate(day.businessDate),
    if (from != null) 'covers': formatCovers(from, day.businessDate),
    'menu_items_ordered_today': report.madeTotal,
    // every number item whose gap isnt 0, biggest first (compared to what the orders explain), with its note
    // no threshold, a gap of 1 piece is listed too
    'gaps': [
      for (final row in rankedGapRows(report))
        {
          'item': row.item.name,
          'unit': row.item.unitWord,
          'used': _number(row.actual!),
          'expected_from_orders': _number(row.expected!),
          'gap': _number(row.gap!.abs()),
          'gap_is': row.gap! > 0
              ? 'more used than orders explain'
              : 'less used than orders explain',
          'note': row.line.note,
        },
    ],
    'number_items_that_matched': [
      for (final row in matchedRows(report)) row.item.name,
    ],
    'restock': [
      for (final row in report.restock)
        {
          'item': row.item.name,
          'left': endText(row),
          'low_level': row.item.lowText,
          'note': row.line.note,
        },
    ],
    // every container finished today, what it held vs what the orders since the last one explain (rule 7)
    // no judging and no difference worked out, the owner reads both numbers
    'containers_finished': [
      for (final check in report.checks)
        {
          'item': check.item.name,
          'containers_finished': check.containers,
          'container_name': check.item.containerName,
          'total_finished': _number(check.containerTotal),
          'expected_from_orders': check.expectedSinceLast == null
              ? null
              : _number(check.expectedSinceLast!),
          'orders_since': check.sinceDate == day.businessDate
              ? 'today'
              : formatShortDate(check.sinceDate),
          'unit': check.item.baseUnit.name,
        },
    ],
    'ordered_with_no_recipe_yet': report.noRecipe,
    'opening_count_items': [
      for (final row in report.usage)
        if (row.isOpening) row.item.name,
    ],
    'opening_count_meaning': openingText,
    'closed_days': [
      for (final date in report.closedDates) formatShortDate(date),
    ],
    'day_note': day.dayNote,
    // the "fine" part, the same text the template uses, empty when there are gaps
    'closing_line': templateSummary(report).fine,
  };
}

// a whole number stays whole (5, not 5.0), others keep up to 2 decimals like the report
num _number(double value) {
  final rounded = roundAmount((value * 100).round() / 100);
  return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
}
