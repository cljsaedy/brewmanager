import '../data/stock_item.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import 'count_table_html.dart';
import 'daily_report.dart';
import 'report_text.dart';

// the subject of the daily email, like "Daily count for Fri, Oct 30"
String dailySubject(String date) => 'Daily count for ${formatLongDate(date)}';

// the owner's daily report (rule 10), plain html with tables, no attachments
// the sections are in this order:
// 1 summary, 2 restock, 3 expected vs actual, 4 container checks, 5 no recipe yet,
// 6 tally, 7 full count table, 8 day note and covered or closed days
// summary = the ai text or the template one, the caller picks
String dailyEmailHtml(DailyReport report, String summary) {
  final html = StringBuffer()
    ..writeln(
      '<h2>${htmlEscape.convert(dailySubject(report.day.businessDate))}</h2>',
    )
    // 1 summary
    ..writeln('<p>${htmlEscape.convert(summary)}</p>');

  // 2 restock recommended, with the End and the low level so the owner sees how low
  html.writeln('<h3>Restock recommended</h3>');
  final restock = report.restock;
  if (restock.isEmpty) {
    html.writeln('<p>None.</p>');
  } else {
    html.writeln('<ul>');
    for (final row in restock) {
      html.writeln(
        '<li>${htmlEscape.convert(row.item.name)}: '
        '${htmlEscape.convert(_endText(row))} '
        '(low level ${htmlEscape.convert(row.item.lowText)})</li>',
      );
    }
    html.writeln('</ul>');
  }

  // 3 expected vs actual, items with recipes, notes beside them
  // estimated items have no gap, an opening count has no numbers (rule 7)
  html.writeln('<h3>Expected vs. actual</h3>');
  final compared = report.compared;
  if (compared.isEmpty) {
    html.writeln('<p>No counted item is in a recipe yet.</p>');
  } else {
    html
      ..writeln(tableOpen)
      ..writeln(headerRow(['Item', 'Used', 'Expected', 'Gap', 'Note']));
    for (final row in compared) {
      final item = row.item;
      html.writeln(
        tableRow([
          item.name,
          usedCell(row),
          row.isOpening ? '—' : amountText(item, row.expected!),
          row.gap == null ? '—' : gapCell(item, row.gap!),
          row.line.note ?? '',
        ]),
      );
    }
    html.writeln('</table>');
    html.writeln(
      '<p>Gap = used − expected. Positive = more used than the tally '
      'explains. Estimated items (counted by level) show no gap, see the '
      'container checks.</p>',
    );
  }

  // 4 container checks
  html.writeln('<h3>Container checks</h3>');
  if (report.checks.isEmpty) {
    html.writeln('<p>No container was finished.</p>');
  } else {
    html.writeln('<ul>');
    for (final check in report.checks) {
      html.writeln(
        '<li>${htmlEscape.convert(checkSentence(check, report.day.businessDate))}</li>',
      );
    }
    html.writeln('</ul>');
  }

  // 5 no recipe yet
  html.writeln('<h3>No recipe yet</h3>');
  if (report.noRecipe.isEmpty) {
    html.writeln('<p>None.</p>');
  } else {
    html.writeln(
      '<p>Tallied but not compared: '
      '${htmlEscape.convert(report.noRecipe.join(', '))}.</p>',
    );
  }

  // 6 tally, menu item + quantity only, never prices
  html.writeln('<h3>Tally</h3>');
  if (report.tally.isEmpty) {
    html.writeln('<p>Nothing was tallied.</p>');
  } else {
    html
      ..writeln(tableOpen)
      ..writeln(headerRow(['Menu item', 'Qty']));
    for (final row in report.tally) {
      html.writeln(tableRow([row.item.name, '${row.qty}']));
    }
    html.writeln('</table>');
  }

  // 7 full count table
  html
    ..writeln('<h3>Count</h3>')
    ..write(countTableHtml(report.countRows));

  // 8 day note, covered dates, closed days
  html.writeln('<h3>Day note</h3>');
  final note = report.day.dayNote;
  html.writeln('<p>${note == null ? 'None.' : htmlEscape.convert(note)}</p>');
  final from = report.day.coversFrom;
  if (from != null) {
    html.writeln(
      '<p>This count covers '
      '${htmlEscape.convert(formatCovers(from, report.day.businessDate))}.</p>',
    );
  }
  if (report.closedDates.isNotEmpty) {
    final dates = report.closedDates.map(formatShortDate).join(', ');
    html.writeln('<p>Closed: ${htmlEscape.convert(dates)}.</p>');
  }

  return html.toString();
}

// End with about when it came from a level (rule 2)
// container items show containers like the logbook, number items like "4 packs"
String _endText(UsageRow row) {
  final item = row.item;
  final end = row.line.endQty;
  final amount = item.countType == CountType.container
      ? formatContainers(end / item.containerSize!, item.containerName)
      : amountText(item, end);
  return row.line.endIsExact ? 'End $amount' : 'End about $amount';
}
