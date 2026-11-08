import '../data/stock_item.dart';
import '../logic/formatting.dart';
import 'count_table_html.dart';
import 'daily_report.dart';
import 'report_text.dart';
import 'summary_parts.dart';

// the subject of the daily email, like "Daily count for Fri, Oct 30"
String dailySubject(String date) => 'Daily count for ${formatLongDate(date)}';

// the owner's daily report (rule 10), plain html with tables, no attachments
// on top: a brown header with the date, then 4 "at a glance" boxes
// then the sections in this order:
// 1 summary, 2 restock, 3 number items used vs expected, 4 container checks, 5 no recipe yet,
// 6 orders today, 7 full count table, 8 day note and covered or closed days
// an empty section is hidden, one "Nothing to flag: ..." line under the summary says which ones had nothing
// the count table always shows
// owner wording: "orders", never "tally" (the barista side keeps "Tally")
// summary = the 5 parts from the ai or the template, the caller picks
// fromAi = true when the ai wrote them, the email says which one the owner is reading
String dailyEmailHtml(
  DailyReport report,
  SummaryParts summary, {
  required bool fromAi,
}) {
  final day = report.day;
  final body = StringBuffer()
    ..write(_glance(report))
    ..write(_summaryHtml(summary, fromAi: fromAi))
    ..write(_nothingMarker);
  // what had nothing, for the "Nothing to flag" line, shown under the summary so it isnt missed
  final nothing = <String>[];

  // 2 restock recommended, with what is left and the low level so the owner sees how low
  final restock = report.restock;
  if (restock.isEmpty) {
    nothing.add('no restock needed');
  } else {
    body
      ..write(
        sectionTitle(
          'Restock recommended',
          hint: 'What is left is at or below the low-stock level.',
        ),
      )
      ..writeln(tableOpen)
      ..writeln(headerRow(['Item', 'Left', 'Low level'], right: {1, 2}));
    for (final row in restock) {
      body.writeln(
        tableRow(
          [row.item.name, endText(row), row.item.lowText],
          right: {1, 2},
        ),
      );
    }
    body.writeln('</table>');
  }

  // 3 number items: used vs what today's orders explain, notes under the name (rule 7)
  // container items are never here, they are compared by container checks
  final compared = report.compared;
  if (compared.isEmpty) {
    nothing.add('no counted pieces to compare with orders');
  } else {
    const right = {1, 2, 3};
    body
      ..write(
        sectionTitle(
          'Used vs. expected (from orders)',
          hint:
              "Items counted in pieces. Based on today's orders, the expected "
              'amount should have been used. Gap = used − expected, '
              '+ means more was used than the orders explain.',
        ),
      )
      ..writeln(tableOpen)
      ..writeln(
        headerRow([
          'Item',
          'Used',
          'Expected (from orders)',
          'Gap',
        ], right: right),
      );
    for (final row in compared) {
      final item = row.item;
      body.writeln(
        htmlRow([
          nameWithNote(item.name, row.line.note),
          htmlEscape.convert(usedCell(row)),
          htmlEscape.convert(
            row.isOpening ? '—' : amountText(item, row.expected!),
          ),
          _gapHtml(row),
        ], right: right),
      );
    }
    body.writeln('</table>');
  }

  // 4 container checks, the only comparison for container items
  if (report.checks.isEmpty) {
    nothing.add('no container finished');
  } else {
    body
      ..write(
        sectionTitle(
          'Container checks',
          hint:
              'When a container is finished: what it held vs. what the '
              'orders since the last one explain.',
        ),
      )
      ..write(
        bulletList([
          for (final check in report.checks)
            checkSentence(check, day.businessDate),
        ]),
      );
  }

  // 5 no recipe yet
  if (report.noRecipe.isEmpty) {
    nothing.add('every ordered item has a recipe');
  } else {
    body
      ..write(
        sectionTitle(
          'No recipe yet',
          hint: 'Ordered today but not compared, add a recipe for them.',
        ),
      )
      ..write(paragraph('${report.noRecipe.join(', ')}.'));
  }

  // 6 orders today, menu item + quantity only, never prices
  if (report.tally.isEmpty) {
    nothing.add('no orders recorded');
  } else {
    body
      ..write(sectionTitle('Orders today', hint: 'Menu items made today.'))
      ..writeln(tableOpen)
      ..writeln(headerRow(['Menu item', 'Qty'], right: {1}));
    for (final row in report.tally) {
      body.writeln(tableRow([row.item.name, '${row.qty}'], right: {1}));
    }
    body.writeln('</table>');
  }

  // 7 full count table, always shown, container items show their level change here (Start → End)
  body
    ..write(
      sectionTitle(
        'Count',
        hint: 'The full logbook. Container items are in containers.',
      ),
    )
    ..write(countTableHtml(report.countRows));

  // 8 day note, covered dates, closed days
  final note = day.dayNote;
  final from = day.coversFrom;
  if (note == null && from == null && report.closedDates.isEmpty) {
    nothing.add('no day note');
  } else {
    body.write(sectionTitle('Day note'));
    if (note != null) {
      body.writeln(
        '<p style="margin:4px 0;font-size:14px;font-style:italic;">'
        '“${htmlEscape.convert(note)}”</p>',
      );
    }
    if (from != null) {
      body.write(
        paragraph('This count covers ${formatCovers(from, day.businessDate)}.'),
      );
    }
    if (report.closedDates.isNotEmpty) {
      final dates = report.closedDates.map(formatShortDate).join(', ');
      body.write(paragraph('Closed: $dates.'));
    }
  }

  // the line goes in the spot kept for it under the summary, now that every section was looked at
  final nothingLine = nothing.isEmpty
      ? ''
      : '<p style="margin:10px 0 0;font-size:13px;color:$textMuted;">'
            'Nothing to flag: ${htmlEscape.convert(nothing.join(', '))}.</p>\n';

  return emailPage(
    label: 'BrewManager · Daily count',
    title: formatLongDate(day.businessDate),
    subtitle: _subtitle(report),
    body: body.toString().replaceFirst(_nothingMarker, nothingLine),
  );
}

// a spot kept under the summary for the "Nothing to flag" line, filled in at the end
const String _nothingMarker = '<!--nothing-to-flag-->';

// the summary on top: a title, then each part under its header, empty parts hidden
// the "fine" part is a closing line with no header
String _summaryHtml(SummaryParts summary, {required bool fromAi}) {
  final html = StringBuffer()
    ..writeln(
      '<div style="background:$cream;border-left:3px solid $caramel;'
      'padding:12px 14px;margin-top:16px;">',
    )
    ..writeln(
      '<div style="font-size:17px;font-weight:bold;color:$espresso;">'
      '${fromAi ? 'AI Summary' : 'Summary'}</div>',
    );
  final parts = summary.byKey;
  for (final key in SummaryParts.headers.keys) {
    final text = parts[key]!;
    if (text.isEmpty) continue;
    html.writeln(
      '<div style="margin-top:10px;font-size:13px;font-weight:bold;'
      'color:$caramel;">${htmlEscape.convert(SummaryParts.headers[key]!)}</div>'
      '<p style="margin:2px 0 0;font-size:15px;line-height:1.5;">'
      '${htmlEscape.convert(text)}</p>',
    );
  }
  if (summary.fine.isNotEmpty) {
    html.writeln(
      '<p style="margin:10px 0 0;font-size:15px;line-height:1.5;">'
      '${htmlEscape.convert(summary.fine)}</p>',
    );
  }
  html
    ..writeln('</div>')
    ..writeln(
      '<p style="margin:4px 0 0;font-size:11px;color:$textMuted;">'
      '${fromAi ? "Written by AI from the app's numbers. The app checked every number." : 'Made by the app from its own numbers. The AI summary was not available.'}'
      '</p>',
    );
  return html.toString();
}

// the small line under the date, like "Covers Oct 29–30 · Submitted 9:42pm"
// submitted_at is utc, the owner reads it in the tablet's local time
String? _subtitle(DailyReport report) {
  final day = report.day;
  final parts = [
    if (day.coversFrom != null)
      'Covers ${formatCovers(day.coversFrom!, day.businessDate)}',
    if (day.submittedAt != null)
      'Submitted ${formatTime(DateTime.parse(day.submittedAt!).toLocal())}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

// the 4 boxes on top: items ordered, to restock, gaps, no recipe yet
// the app counts these, a box is amber when it needs a look and is not 0
String _glance(DailyReport report) {
  String box(String label, int value, {bool warn = false}) {
    final alert = warn && value > 0;
    final bg = alert ? warnBg : cream;
    final color = alert ? warnText : textMuted;
    return '<td width="25%" style="padding:4px;">'
        '<div style="background:$bg;padding:8px 10px;">'
        '<div style="font-size:11px;color:$color;">${htmlEscape.convert(label)}</div>'
        '<div style="font-size:20px;font-weight:bold;'
        'color:${alert ? warnText : textMain};">$value</div>'
        '</div></td>';
  }

  return '<table width="100%" cellpadding="0" cellspacing="0" '
      'style="border-collapse:collapse;"><tr>'
      '${box('Items ordered', report.madeTotal)}'
      '${box('To restock', report.restock.length, warn: true)}'
      '${box('Gaps', gapRows(report).length, warn: true)}'
      '${box('No recipe yet', report.noRecipe.length, warn: true)}'
      '</tr></table>\n';
}

// the gap cell: "—" when there is no gap, a green 0 when it matched,
// an amber tag when it didnt (more or less), the color only says there is a difference, never why
String _gapHtml(UsageRow row) {
  final gap = row.gap;
  if (gap == null) return '<span style="color:$textMuted;">—</span>';
  final text = htmlEscape.convert(gapCell(row.item, gap));
  if (text == '0') return '<span style="color:$okText;">0</span>';
  return '<span style="background:$warnBg;color:$warnText;'
      'padding:2px 6px;white-space:nowrap;">$text</span>';
}
