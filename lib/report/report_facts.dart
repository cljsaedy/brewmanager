import '../logic/formatting.dart';
import '../logic/units.dart';
import 'daily_report.dart';
import 'report_text.dart';

// the facts the ai gets (rule 10): every number already worked out by the app, plus the notes word for word
// never prices or anything personal, only stock items, menu item names, counts and notes
// numbers are rounded to 2 decimals the same way the report shows them, so the ai can copy them exactly
Map<String, Object?> reportFacts(DailyReport report) {
  final day = report.day;
  final from = day.coversFrom;

  return {
    'date': formatLongDate(day.businessDate),
    if (from != null) 'covers': formatCovers(from, day.businessDate),
    'menu_items_tallied': report.madeTotal,
    'restock_recommended': [
      for (final row in report.restock)
        {
          'item': row.item.name,
          'end': _number(row.line.endQty),
          'unit': row.item.unitWord,
          'low_level': row.item.lowText,
        },
    ],
    // exact items: used, expected and the gap (positive = more used than the tally explains)
    'exact_items': [
      for (final row in report.compared)
        if (row.gap != null)
          {
            'item': row.item.name,
            'used': _number(row.actual!),
            'expected': _number(row.expected!),
            'gap': _number(row.gap!),
            'unit': row.item.unitWord,
          },
    ],
    // estimated items: about how much was used and what the recipes expect, there is no gap
    'estimated_items': [
      for (final row in report.compared)
        if (!row.isOpening && !row.actualIsExact)
          {
            'item': row.item.name,
            'about_used': _number(row.actual!),
            'expected': _number(row.expected!),
            'unit': row.item.unitWord,
          },
    ],
    'container_checks': [
      for (final check in report.checks)
        {
          'item': check.item.name,
          'containers_finished': check.containers,
          'container_name': check.item.containerName,
          'total_used': _number(check.containerTotal),
          'recipes_explain': check.expectedSinceLast == null
              ? null
              : _number(check.expectedSinceLast!),
          'since': check.sinceDate == day.businessDate
              ? 'today'
              : formatShortDate(check.sinceDate),
          'unit': check.item.baseUnit.name,
        },
    ],
    'no_recipe_yet': report.noRecipe,
    'opening_count_items': [
      for (final row in report.usage)
        if (row.isOpening) row.item.name,
    ],
    'opening_count_meaning': openingText,
    'closed_days': [
      for (final date in report.closedDates) formatShortDate(date),
    ],
    'item_notes': [
      for (final row in report.usage)
        if (row.line.note != null)
          {'item': row.item.name, 'note': row.line.note},
    ],
    'day_note': day.dayNote,
  };
}

// a whole number stays whole (5, not 5.0), others keep up to 2 decimals like the report
num _number(double value) {
  final rounded = roundAmount((value * 100).round() / 100);
  return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
}
