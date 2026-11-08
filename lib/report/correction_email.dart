import '../count/count_cells.dart';
import '../data/count_line.dart';
import '../data/stock_item.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import 'count_table_html.dart';

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
  // like "2.5 → 3 bottles", "6 → 8 packs" or "6 → 8 pcs"
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
      newText = amountText(stock, newAmount);
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
// same look as the daily email (brown header, light tables), no attachments
// every text from the db is escaped inside the helpers so a note with < or & cant break the email
String correctionEmailHtml({
  required String date,
  required List<CorrectionEntry> changes,
  required List<CountRow> rows,
}) {
  final body = StringBuffer()
    ..write(
      sectionTitle(
        'What changed',
        hint: 'Each change with the reason the staff gave.',
      ),
    )
    ..write(
      bulletList([
        for (final change in changes)
          '${change.description}. Reason: ${change.reason}.',
      ]),
    )
    ..write(
      paragraph(
        "The day's usage numbers were worked out again with these changes.",
        muted: true,
      ),
    )
    ..write(
      sectionTitle(
        'Corrected count',
        hint:
            'The full logbook after the changes. Container items are in containers.',
      ),
    )
    ..write(countTableHtml(rows));

  return emailPage(
    label: 'BrewManager · Correction',
    title: formatLongDate(date),
    subtitle: '${changes.length} ${changes.length == 1 ? 'change' : 'changes'}',
    body: body.toString(),
  );
}
