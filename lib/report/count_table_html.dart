import 'dart:convert';

import '../count/count_cells.dart';
import '../data/count_line.dart';

// every text from the db goes through escape so a note with < or & cant break the email
const HtmlEscape htmlEscape = HtmlEscape();

// the count table, Start / In / Out / End with notes, same cells as the logbook
// the daily report and the correction email both use it
String countTableHtml(List<CountRow> rows) {
  final html = StringBuffer()
    ..writeln(tableOpen)
    ..writeln(headerRow(['Item', 'Unit', 'Start', 'In', 'Out', 'End', 'Note']));
  for (final row in rows) {
    final item = row.item;
    final line = row.line;
    html.writeln(
      tableRow([
        item.name,
        unitText(item),
        shownAmount(item, line.startQty),
        shownAmount(item, line.inQty),
        outText(item, line),
        shownAmount(item, line.endQty),
        line.note ?? '',
      ]),
    );
  }
  html.writeln('</table>');
  return html.toString();
}

// plain table with lines, email apps ignore most css so it stays simple
const String tableOpen =
    '<table border="1" cellpadding="6" style="border-collapse: collapse">';

String headerRow(List<String> cells) =>
    '<tr>${cells.map((cell) => '<th>${htmlEscape.convert(cell)}</th>').join()}</tr>';

String tableRow(List<String> cells) =>
    '<tr>${cells.map((cell) => '<td>${htmlEscape.convert(cell)}</td>').join()}</tr>';
