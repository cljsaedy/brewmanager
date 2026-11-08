import 'dart:convert';

import '../count/count_cells.dart';
import '../data/count_line.dart';
import '../data/stock_item.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';

// one logged change, a row of the corrections table with the name of what it changed
class CorrectionEntry {
  const CorrectionEntry({
    required this.target,
    required this.field,
    required this.name,
    required this.oldValue,
    required this.newValue,
    required this.reason,
    required this.correctedAt,
    this.item,
  });

  // count, tally or day
  final String target;
  // end, in, out or note for a count line, qty for a tally line, day_note for the day
  final String field;
  // the stock item or menu item name, "Day note" for the day
  final String name;
  // numbers are base units as text, notes are the text itself, null = empty
  final String? oldValue;
  final String? newValue;
  final String reason;
  // utc iso text
  final String correctedAt;
  // the stock item of a count line, so its amounts can show in containers
  final StockItem? item;

  // like "Caramel syrup End 2.5 → 3 bottles"
  String get description {
    switch (field) {
      case 'end':
        return '$name End ${_amountChange()}';
      case 'in':
        return '$name In ${_amountChange()}';
      case 'out':
        return '$name Out $oldValue → $newValue';
      case 'note':
        return '$name note ${_textChange()}';
      case 'qty':
        return '$name tally $oldValue → $newValue';
      default:
        return 'Day note ${_textChange()}';
    }
  }

  // an amount the way the logbook shows it, the new one with its unit
  // like "2.5 → 3 bottles" or "6 → 8 pcs"
  String _amountChange() {
    final stock = item!;
    final oldAmount = double.parse(oldValue!);
    final newAmount = double.parse(newValue!);
    final String newText;
    if (stock.countType == CountType.container) {
      newText = formatContainers(
        newAmount / stock.containerSize!,
        stock.containerName,
      );
    } else {
      newText = formatWithUnit(newAmount, stock.baseUnit.name);
    }
    return '${shownAmount(stock, oldAmount)} → $newText';
  }

  // like "“cap loose” → “cap was loose”", an empty note shows as (none)
  String _textChange() {
    String quoted(String? text) => text == null ? '(none)' : '“$text”';
    return '${quoted(oldValue)} → ${quoted(newValue)}';
  }
}

// the subject of a correction email, like "Correction on Fri, Oct 30"
String correctionSubject(String date) =>
    'Correction on ${formatLongDate(date)}';

// a short correction email: what changed and why, then the corrected count table (rule 4)
// plain html with a table, no attachments, feature 9 sends it from the outbox
// every text from the db goes through escape so a note with < or & cant break the email
String correctionEmailHtml({
  required String date,
  required List<CorrectionEntry> changes,
  required List<CountRow> rows,
}) {
  const escape = HtmlEscape();
  final html = StringBuffer()
    ..writeln('<h2>${escape.convert(correctionSubject(date))}</h2>')
    ..writeln('<ul>');
  for (final change in changes) {
    html.writeln(
      '<li>${escape.convert(change.description)}. '
      'Reason: ${escape.convert(change.reason)}.</li>',
    );
  }
  html
    ..writeln('</ul>')
    ..writeln('<h3>Corrected count</h3>')
    ..writeln(
      '<table border="1" cellpadding="6" style="border-collapse: collapse">',
    )
    ..writeln(
      '<tr><th>Item</th><th>Unit</th><th>Start</th><th>In</th>'
      '<th>Out</th><th>End</th><th>Note</th></tr>',
    );
  for (final row in rows) {
    final item = row.item;
    final line = row.line;
    final cells = [
      item.name,
      unitText(item),
      shownAmount(item, line.startQty),
      shownAmount(item, line.inQty),
      outText(item, line),
      shownAmount(item, line.endQty),
      line.note ?? '',
    ];
    html.writeln(
      '<tr>${cells.map((cell) => '<td>${escape.convert(cell)}</td>').join()}</tr>',
    );
  }
  html.writeln('</table>');
  return html.toString();
}
