import '../data/stock_item.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import 'count_table_html.dart';
import 'daily_report.dart';
import 'report_text.dart';

// the subject of the daily email, like "Daily count for Fri, Oct 30"
String dailySubject(String date) => 'Daily count for ${formatLongDate(date)}';

// the owner's daily report (rule 10), plain html with tables, no attachments
// on top: a brown header with the date, then 4 "at a glance" boxes
// then the sections in this order:
// 1 summary, 2 restock, 3 expected vs actual, 4 container checks, 5 no recipe yet,
// 6 tally, 7 full count table, 8 day note and covered or closed days
// an empty section still shows and says "None." so the owner knows it was checked
// summary = bullet points from the ai or the template, the caller picks
// fromAi = true when the ai wrote them, the email says which one the owner is reading
String dailyEmailHtml(
  DailyReport report,
  List<String> summary, {
  required bool fromAi,
}) {
  final day = report.day;
  final body = StringBuffer()
    ..write(_glance(report))
    // 1 summary in a cream box with a caramel line on the left
    ..writeln(
      '<div style="background:$cream;border-left:3px solid $caramel;'
      'padding:8px 12px;margin-top:16px;">',
    )
    ..write(bulletList(summary))
    ..writeln('</div>')
    ..writeln(
      '<p style="margin:4px 0 0;font-size:11px;color:$textMuted;">'
      '${fromAi ? "Summary written by AI from the app's numbers. The app checked every number." : 'Summary made by the app from its own numbers.'}'
      '</p>',
    );

  // 2 restock recommended, with the End and the low level so the owner sees how low
  body.write(
    sectionTitle(
      'Restock recommended',
      hint: 'End is at or below the low-stock level.',
    ),
  );
  final restock = report.restock;
  if (restock.isEmpty) {
    body.write(paragraph('None.', muted: true));
  } else {
    body
      ..writeln(tableOpen)
      ..writeln(headerRow(['Item', 'End', 'Low level'], right: {1, 2}));
    for (final row in restock) {
      body.writeln(
        tableRow(
          [row.item.name, _endText(row), row.item.lowText],
          right: {1, 2},
        ),
      );
    }
    body.writeln('</table>');
  }

  // 3 expected vs actual, items with recipes, notes under the name
  // estimated items have no gap, an opening count has no numbers (rule 7)
  body.write(
    sectionTitle(
      'Expected vs. actual',
      hint:
          'Expected = what the recipes say the tally used. '
          'Gap = used − expected, + means more was used than the tally explains. '
          'Items counted by level are estimated and have no gap, '
          'see the container checks.',
    ),
  );
  final compared = report.compared;
  if (compared.isEmpty) {
    body.write(paragraph('No counted item is in a recipe yet.', muted: true));
  } else {
    const right = {1, 2, 3};
    body
      ..writeln(tableOpen)
      ..writeln(headerRow(['Item', 'Used', 'Expected', 'Gap'], right: right));
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

  // 4 container checks
  body.write(
    sectionTitle(
      'Container checks',
      hint:
          'When a container is finished: what it held vs. what the recipes explain.',
    ),
  );
  if (report.checks.isEmpty) {
    body.write(paragraph('None. No container was finished.', muted: true));
  } else {
    body.write(
      bulletList([
        for (final check in report.checks)
          checkSentence(check, day.businessDate),
      ]),
    );
  }

  // 5 no recipe yet
  body.write(
    sectionTitle(
      'No recipe yet',
      hint: 'Tallied menu items the app could not compare.',
    ),
  );
  if (report.noRecipe.isEmpty) {
    body.write(paragraph('None.', muted: true));
  } else {
    body.write(paragraph('${report.noRecipe.join(', ')}.'));
  }

  // 6 tally, menu item + quantity only, never prices
  body.write(sectionTitle('Tally', hint: 'Menu items made today.'));
  if (report.tally.isEmpty) {
    body.write(paragraph('None. Nothing was tallied.', muted: true));
  } else {
    body
      ..writeln(tableOpen)
      ..writeln(headerRow(['Menu item', 'Qty'], right: {1}));
    for (final row in report.tally) {
      body.writeln(tableRow([row.item.name, '${row.qty}'], right: {1}));
    }
    body.writeln('</table>');
  }

  // 7 full count table
  body
    ..write(
      sectionTitle(
        'Count',
        hint: 'The full logbook. Container items are in containers.',
      ),
    )
    ..write(countTableHtml(report.countRows));

  // 8 day note, covered dates, closed days
  body.write(sectionTitle('Day note'));
  final note = day.dayNote;
  if (note == null) {
    body.write(paragraph('None.', muted: true));
  } else {
    body.writeln(
      '<p style="margin:4px 0;font-size:14px;font-style:italic;">'
      '“${htmlEscape.convert(note)}”</p>',
    );
  }
  final from = day.coversFrom;
  if (from != null) {
    body.write(
      paragraph('This count covers ${formatCovers(from, day.businessDate)}.'),
    );
  }
  if (report.closedDates.isNotEmpty) {
    final dates = report.closedDates.map(formatShortDate).join(', ');
    body.write(paragraph('Closed: $dates.'));
  }

  return emailPage(
    label: 'BrewManager · Daily count',
    title: formatLongDate(day.businessDate),
    subtitle: _subtitle(report),
    body: body.toString(),
  );
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

// the 4 boxes on top: items made, to restock, gaps, no recipe yet
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
      '${box('Items made', report.madeTotal)}'
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

// End with about when it came from a level (rule 2)
// container items show containers like the logbook, number items like "4 packs"
String _endText(UsageRow row) {
  final item = row.item;
  final end = row.line.endQty;
  final amount = item.countType == CountType.container
      ? formatContainers(end / item.containerSize!, item.containerName)
      : amountText(item, end);
  return row.line.endIsExact ? amount : 'about $amount';
}
