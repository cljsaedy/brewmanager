import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_line.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/report_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/count_math.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/report/daily_email.dart';
import 'package:brewmanager/report/report_text.dart';
import 'package:brewmanager/report/template_summary.dart';

import '../helpers/test_database.dart';

// a 2000 ml bottle, low at 1 bottle
const StockItem syrup = StockItem(
  name: 'Caramel syrup',
  category: 'Syrups',
  baseUnit: BaseUnit.ml,
  countType: CountType.container,
  containerLabel: 'bottle',
  containerSize: 2000,
  lowMode: LowMode.containers,
  lowValue: 1,
);

// low at 5 packs
const StockItem friesPack = StockItem(
  name: 'Fries pack',
  category: 'Food',
  baseUnit: BaseUnit.pcs,
  countType: CountType.number,
  containerLabel: 'pack',
  lowMode: LowMode.exact,
  lowValue: 5,
);

// the scripted day, worked out by hand:
//
// nov 1 (opening count): fries 8, syrup 2 sealed + 50% (5000 ml, estimated)
// nov 2: 2 french fries, 10 lattes, 1 waffle tallied
//   fries: 8 -> 5, actual 3, expected 2 x 1 = 2, gap +1 (exact)
//          End 5 is at the low level of 5, so restock
//   syrup: 1 bottle finished, then 1 sealed + full = 4000 ml (estimated)
//          about 1000 ml used, expected 10 x 30 = 300 ml, no gap
//          container check: the first after an opening count at 50%,
//          so 1000 ml + 2000 x (1 - 1) = 1000 ml, recipes explain 300 ml since nov 1
//   waffle has no recipe, water is "no recipe needed" so it is not listed
void main() {
  late Database db;
  late CountStore counts;
  late DateTime now;
  late int syrupId;
  late int friesId;
  late int waffleId;

  setUp(() async {
    db = await openTestDatabase();
    now = DateTime.utc(2026, 11, 1, 10);
    counts = CountStore(db, clock: () => now);
    final stock = StockItemStore(db);
    final menu = MenuItemStore(db, clock: () => now);
    final recipes = RecipeStore(db, clock: () => now);

    syrupId = await stock.add(syrup);
    friesId = await stock.add(friesPack);
    final latteId = await menu.add(
      const MenuItem(name: 'Latte', category: 'Coffee'),
    );
    final friesMenuId = await menu.add(
      const MenuItem(name: 'French Fries', category: 'Food'),
    );
    waffleId = await menu.add(const MenuItem(name: 'Waffle', category: 'Food'));
    final waterId = await menu.add(
      const MenuItem(name: 'Water', category: 'Drinks', noStock: true),
    );
    await recipes.addLine(latteId, syrupId, 30);
    await recipes.addLine(friesMenuId, friesId, 1);

    // nov 1
    var day = await counts.loadDraft();
    await counts.saveNumberCount(rowOf(day, friesId).line.id, 8);
    await counts.saveContainerCount(
      rowOf(day, syrupId),
      sealed: 2,
      level: level50,
      exactQty: null,
    );
    await counts.submits.submit(day.day.id, date: '2026-11-01');
    now = DateTime.utc(2026, 11, 2, 10);

    // nov 2
    day = await counts.loadDraft();
    final dayId = day.day.id;
    await counts.saveNumberCount(rowOf(day, friesId).line.id, 5);
    await counts.finishContainer(rowOf(day, syrupId));
    for (var i = 0; i < 2; i++) {
      await counts.tally.add(dayId, friesMenuId);
    }
    for (var i = 0; i < 10; i++) {
      await counts.tally.add(dayId, latteId);
    }
    await counts.tally.add(dayId, waffleId);
    await counts.tally.add(dayId, waterId);
    await counts.saveDayNote(dayId, 'power <b>outage</b> at 3pm');
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> submitNov2() async {
    final day = await counts.loadDraft();
    await counts.submits.submit(day.day.id, date: '2026-11-02');
    return day.day.id;
  }

  group('the scripted day', () {
    test('the numbers match the hand-worked ones', () async {
      final report = await ReportStore(db).load(await submitNov2());

      final fries = report.usage.firstWhere((row) => row.item.id == friesId);
      expect(fries.actual, 3);
      expect(fries.expected, 2);
      expect(fries.gap, 1);
      expect(fries.restock, isTrue);

      final syrupRow = report.usage.firstWhere((row) => row.item.id == syrupId);
      expect(syrupRow.actual, 1000);
      expect(syrupRow.actualIsExact, isFalse);
      expect(syrupRow.expected, 300);
      expect(syrupRow.gap, isNull);
      expect(syrupRow.restock, isFalse);

      final check = report.checks.single;
      expect(check.containerTotal, 1000);
      expect(check.expectedSinceLast, 300);
      expect(check.sinceDate, '2026-11-01');

      expect(report.noRecipe, ['Waffle']);
      expect(report.madeTotal, 14);
    });

    test('the sentences', () async {
      final report = await ReportStore(db).load(await submitNov2());
      final fries = report.usage.firstWhere((row) => row.item.id == friesId);
      final syrupRow = report.usage.firstWhere((row) => row.item.id == syrupId);

      expect(
        gapSentence(fries),
        'Fries pack: 1 pack more used than the tally explains.',
      );
      expect(gapCell(fries.item, fries.gap!), '+1 pack');
      expect(usedCell(syrupRow), 'about 1,000 ml (estimated)');
      expect(
        estimatedSentence(syrupRow),
        'Caramel syrup: about 1,000 ml used (estimated from bottle level). '
        'Recipes expect 300 ml.',
      );
      expect(
        checkSentence(report.checks.single, '2026-11-02'),
        'Caramel syrup: 1 bottle (1,000 ml) finished. '
        'Recipes explain 300 ml since Nov 1.',
      );
    });

    test('the template summary', () async {
      final report = await ReportStore(db).load(await submitNov2());

      expect(templateSummary(report), [
        '14 menu items were tallied.',
        'Restock recommended: Fries pack.',
        'Fries pack: 1 pack more used than the tally explains.',
        'Caramel syrup: 1 bottle (1,000 ml) finished. '
            'Recipes explain 300 ml since Nov 1.',
        'No recipe yet: Waffle.',
        'Day note: “power <b>outage</b> at 3pm”.',
      ]);
    });

    test('the ai text becomes bullets', () {
      expect(
        summaryBullets(
          '- **14** menu items were tallied.\n\n'
          '* Fries pack is low.\n'
          '• Waffle has no recipe yet.\n'
          'A line with no mark.',
        ),
        [
          '14 menu items were tallied.',
          'Fries pack is low.',
          'Waffle has no recipe yet.',
          'A line with no mark.',
        ],
      );
      // a plain paragraph is 1 bullet, nothing is lost
      expect(summaryBullets('One. Two.'), ['One. Two.']);
    });
  });

  group('submit', () {
    test('queues the daily email with the template summary', () async {
      final dayId = await submitNov2();

      final email = (await db.query(
        'outbox',
        where: "kind = 'daily' AND day_id = ?",
        whereArgs: [dayId],
      )).single;
      expect(email['subject'], 'Daily count for Mon, Nov 2');
      expect(email['status'], 'queued');
      final html = email['html_body'] as String;
      expect(html, contains('14 menu items were tallied.'));

      final day = (await db.query(
        'business_days',
        where: 'id = ?',
        whereArgs: [dayId],
      )).single;
      expect(day['summary_source'], 'template');
    });

    test('every submit queues 1 daily email', () async {
      await submitNov2();

      expect(await db.query('outbox', where: "kind = 'daily'"), hasLength(2));
    });
  });

  group('the email', () {
    test('has the 8 sections in order', () async {
      final report = await ReportStore(db).load(await submitNov2());
      final html = dailyEmailHtml(
        report,
        templateSummary(report),
        fromAi: false,
      );

      final titles = [
        '14 menu items were tallied.',
        'Restock recommended</h3>',
        'Expected vs. actual</h3>',
        'Container checks</h3>',
        'No recipe yet</h3>',
        'Tally</h3>',
        'Count</h3>',
        'Day note</h3>',
      ];
      final places = [for (final title in titles) html.indexOf(title)];
      expect(places, everyElement(greaterThan(-1)));
      expect(places, orderedEquals([...places]..sort()));
    });

    test('estimated items have no gap, exact ones do', () async {
      final report = await ReportStore(db).load(await submitNov2());
      // the cells as text, like "Fries pack|3 packs|2 packs|+1 pack|"
      final cells = cellText(
        dailyEmailHtml(report, ['summary'], fromAi: false),
      );

      expect(
        cells,
        contains('Caramel syrup|about 1,000 ml (estimated)|300 ml|—|'),
      );
      expect(cells, contains('Fries pack|3 packs|2 packs|+1 pack|'));
    });

    test('notes are escaped so they cant break the email', () async {
      final report = await ReportStore(db).load(await submitNov2());
      final html = dailyEmailHtml(report, ['summary'], fromAi: false);

      expect(html, contains('power &lt;b&gt;outage&lt;&#47;b&gt; at 3pm'));
      expect(html, isNot(contains('<b>outage')));
    });

    test('no prices go in the email', () async {
      final report = await ReportStore(db).load(await submitNov2());
      final html = dailyEmailHtml(
        report,
        templateSummary(report),
        fromAi: false,
      );

      expect(html, isNot(contains('₱')));
      expect(html.toLowerCase(), isNot(contains('price')));
    });
  });

  group('history stays right', () {
    test('a recipe added after submit doesnt change "no recipe yet"', () async {
      final dayId = await submitNov2();
      now = DateTime.utc(2026, 11, 3, 10);
      await RecipeStore(db, clock: () => now).addLine(waffleId, friesId, 1);

      final report = await ReportStore(db).load(dayId);
      expect(report.noRecipe, ['Waffle']);
    });

    test('the opening count day has no numbers', () async {
      final day1 =
          (await db.query(
                'business_days',
                where: "business_date = '2026-11-01'",
              )).single['id']
              as int;

      final report = await ReportStore(db).load(day1);
      final fries = report.usage.firstWhere((row) => row.item.id == friesId);
      expect(fries.isOpening, isTrue);
      expect(usedCell(fries), openingText);
      expect(
        templateSummary(report),
        contains(
          // by category then name, Food comes before Syrups
          'Opening count for Fries pack, Caramel syrup, '
          'comparing starts next count.',
        ),
      );
    });
  });

  group('skipped days', () {
    test('closed days are listed', () async {
      final day = await counts.loadDraft();
      await counts.submits.submit(
        day.day.id,
        date: '2026-11-04',
        skippedDaysOpen: false,
      );

      final report = await ReportStore(db).load(day.day.id);
      expect(report.closedDates, ['2026-11-02', '2026-11-03']);
      expect(templateSummary(report), contains('Closed: Nov 2, Nov 3.'));
    });

    test('open skipped days show what the count covers', () async {
      final day = await counts.loadDraft();
      await counts.submits.submit(day.day.id, date: '2026-11-03');

      final report = await ReportStore(db).load(day.day.id);
      expect(report.closedDates, isEmpty);
      expect(templateSummary(report), contains('This count covers Nov 2–3.'));
    });
  });
}

// the email's table cells as plain text, each cell ends with |
// so a test can check a row without caring about the styles
String cellText(String html) => html
    .replaceAll(RegExp(r'</t[dh]>'), '|')
    .replaceAll(RegExp(r'<[^>]+>'), '');

CountRow rowOf(DraftDay day, int itemId) {
  return day.rows.firstWhere((row) => row.item.id == itemId);
}
