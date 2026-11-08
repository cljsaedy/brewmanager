import 'dart:convert';

import '../count/count_cells.dart';
import '../data/count_line.dart';

// every text from the db goes through escape so a note with < or & cant break the email
const HtmlEscape htmlEscape = HtmlEscape();

// the email look, same coffee colors as the app theme (lib/theme)
// email apps (gmail, outlook) ignore <style> blocks and most new css,
// so every style is written inline on each tag and the layout is plain tables
const String espresso = '#5B3A29';
const String caramel = '#C8873A';
const String cream = '#F6F1EB';
const String divider = '#E8DFD6';
const String textMain = '#2B211C';
const String textMuted = '#7A6A60';
const String warnText = '#B26A00';
const String warnBg = '#FDF0DC';
const String okText = '#2E7D4F';

// the whole email: a cream page with a white card in the middle, 600px wide so it reads well on a phone and a computer
// title = the big line in the brown header, like the date, small = the lines around it
String emailPage({
  required String label,
  required String title,
  String? subtitle,
  required String body,
}) {
  final html = StringBuffer()
    ..writeln(
      '<table width="100%" cellpadding="0" cellspacing="0" '
      'style="background:$cream;padding:16px 0;">'
      '<tr><td align="center">',
    )
    ..writeln(
      '<table width="600" cellpadding="0" cellspacing="0" '
      'style="max-width:600px;width:100%;background:#FFFFFF;'
      'border:1px solid $divider;border-collapse:separate;'
      'font-family:Arial,Helvetica,sans-serif;color:$textMain;">',
    )
    // brown header
    ..writeln(
      '<tr><td style="background:$espresso;padding:16px 20px;">'
      '<div style="font-size:12px;color:$cream;">${htmlEscape.convert(label)}</div>'
      '<div style="font-size:22px;font-weight:bold;color:#FFFFFF;margin-top:2px;">'
      '${htmlEscape.convert(title)}</div>'
      '${subtitle == null ? '' : '<div style="font-size:12px;color:$cream;margin-top:2px;">${htmlEscape.convert(subtitle)}</div>'}'
      '</td></tr>',
    )
    ..writeln('<tr><td style="padding:16px 20px;">')
    ..write(body)
    ..writeln('</td></tr>')
    // small footer
    ..writeln(
      '<tr><td style="padding:12px 20px;border-top:1px solid $divider;'
      'font-size:11px;color:$textMuted;">'
      'Sent by BrewManager. Notes are written by the staff, word for word.'
      '</td></tr>',
    )
    ..writeln('</table>')
    ..writeln('</td></tr></table>');
  return html.toString();
}

// a section title with a short line under it saying what the section means
String sectionTitle(String title, {String? hint}) {
  final html = StringBuffer(
    '<h3 style="margin:20px 0 2px;font-size:16px;color:$espresso;">'
    '${htmlEscape.convert(title)}</h3>',
  );
  if (hint != null) {
    html.write(
      '<p style="margin:0 0 8px;font-size:12px;color:$textMuted;">'
      '${htmlEscape.convert(hint)}</p>',
    );
  }
  return '$html\n';
}

// a plain line of text, like "None."
String paragraph(String text, {bool muted = false}) =>
    '<p style="margin:4px 0;font-size:14px;'
    'color:${muted ? textMuted : textMain};">${htmlEscape.convert(text)}</p>\n';

// a bullet list, each item is plain text
String bulletList(List<String> items) {
  final html = StringBuffer('<ul style="margin:4px 0;padding-left:20px;">');
  for (final item in items) {
    html.write(
      '<li style="margin:3px 0;font-size:14px;line-height:1.5;">'
      '${htmlEscape.convert(item)}</li>',
    );
  }
  html.writeln('</ul>');
  return html.toString();
}

// the item name with its note under it in quotes, a note is shown word for word (rule 9)
// gives back html, both parts are escaped
String nameWithNote(String name, String? note) {
  final html = StringBuffer(htmlEscape.convert(name));
  if (note != null && note.isNotEmpty) {
    html.write(
      '<br><span style="font-size:12px;color:$textMuted;font-style:italic;">'
      '“${htmlEscape.convert(note)}”</span>',
    );
  }
  return html.toString();
}

// the count table, Start / In / Out / End, same cells as the logbook
// grouped by category like the count tab, the rows already come sorted by category then name
// the note goes under the item name so the table stays narrow enough for a phone
// the daily report and the correction email both use it
String countTableHtml(List<CountRow> rows) {
  const right = {2, 3, 4, 5};
  final html = StringBuffer()
    ..writeln(tableOpen)
    ..writeln(
      headerRow(['Item', 'Unit', 'Start', 'In', 'Out', 'End'], right: right),
    );
  String? category;
  for (final row in rows) {
    final item = row.item;
    final line = row.line;
    if (item.category != category) {
      category = item.category;
      html.writeln(groupRow(category, columns: 6));
    }
    html.writeln(
      htmlRow([
        nameWithNote(item.name, line.note),
        htmlEscape.convert(unitText(item)),
        htmlEscape.convert(shownAmount(item, line.startQty)),
        htmlEscape.convert(shownAmount(item, line.inQty)),
        htmlEscape.convert(outText(item, line)),
        htmlEscape.convert(shownAmount(item, line.endQty)),
      ], right: right),
    );
  }
  html.writeln('</table>');
  return html.toString();
}

// a table with light lines between rows instead of a heavy black grid
const String tableOpen =
    '<table width="100%" cellpadding="0" cellspacing="0" '
    'style="border-collapse:collapse;font-size:14px;">';

// cell padding of every table cell
const String _pad = 'padding:7px 8px;';

// the header row, cream with muted text
// right = the column numbers (from 0) that hold numbers, they line up on the right
String headerRow(List<String> cells, {Set<int> right = const {}}) {
  final html = StringBuffer('<tr style="background:$cream;">');
  for (var i = 0; i < cells.length; i++) {
    html.write(
      '<th align="${right.contains(i) ? 'right' : 'left'}" '
      'style="$_pad font-size:12px;font-weight:normal;color:$textMuted;">'
      '${htmlEscape.convert(cells[i])}</th>',
    );
  }
  html.write('</tr>');
  return html.toString();
}

// a row of plain text cells, each one escaped here
String tableRow(List<String> cells, {Set<int> right = const {}}) =>
    htmlRow([for (final cell in cells) htmlEscape.convert(cell)], right: right);

// a row of cells that are already html (and already escaped), like a name with its note or a gap tag
String htmlRow(List<String> cells, {Set<int> right = const {}}) {
  final html = StringBuffer('<tr>');
  for (var i = 0; i < cells.length; i++) {
    html.write(
      '<td align="${right.contains(i) ? 'right' : 'left'}" valign="top" '
      'style="$_pad border-top:1px solid $divider;">${cells[i]}</td>',
    );
  }
  html.write('</tr>');
  return html.toString();
}

// a category row across the whole table, like "Syrups"
String groupRow(String title, {required int columns}) =>
    '<tr><td colspan="$columns" style="padding:10px 8px 4px;font-size:12px;'
    'font-weight:bold;color:$caramel;border-top:1px solid $divider;">'
    '${htmlEscape.convert(title)}</td></tr>';
