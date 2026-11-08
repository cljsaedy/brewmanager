import 'package:sqflite/sqflite.dart';

import '../logic/analytics_math.dart';
import '../report/daily_report.dart';
import 'stock_item.dart';

// 1 container check with the day it happened
class DatedCheck {
  const DatedCheck({required this.date, required this.check});

  // YYYY-MM-DD
  final String date;
  final CheckRow check;
}

// 1 menu item ordered with no recipe yet, and on how many days in the chosen dates
class NoRecipeEntry {
  const NoRecipeEntry({required this.name, required this.days});

  final String name;
  final int days;
}

// everything the analytics tab shows for the chosen dates
class Analytics {
  const Analytics({
    required this.numberItems,
    required this.daysByItem,
    required this.checks,
    required this.noRecipe,
  });

  // number items counted in these dates, by category then name (archived ones too, history stays right)
  final List<StockItem> numberItems;
  // each number item's days, oldest first, keyed by stock item id
  final Map<int, List<UsagePoint>> daysByItem;
  // every container finished in these dates, newest first
  final List<DatedCheck> checks;
  final List<NoRecipeEntry> noRecipe;
}

// reads what submit and corrections saved, for the owner's analytics tab (feature 10)
// it only reads, every number was already worked out at submit
// only submitted days, a closed day has no count
class AnalyticsStore {
  AnalyticsStore(this._db);

  final Database _db;

  // the newest submitted business date, the chosen dates end there, null before the first submit
  Future<String?> lastSubmittedDate() async {
    final rows = await _db.rawQuery(
      "SELECT MAX(business_date) AS date FROM business_days WHERE status = 'submitted'",
    );
    return rows.first['date'] as String?;
  }

  // from and to are YYYY-MM-DD, both days included
  Future<Analytics> load(String from, String to) async {
    // number items only, container items have no daily gap (rule 7)
    // actual_qty null = an opening count, it has no usage so it is left out
    final resultRows = await _db.rawQuery(
      '''
      SELECT day_results.stock_item_id, day_results.actual_qty,
             day_results.expected_qty, day_results.gap,
             business_days.business_date
      FROM day_results
      JOIN business_days ON business_days.id = day_results.day_id
      JOIN stock_items ON stock_items.id = day_results.stock_item_id
      WHERE business_days.status = 'submitted'
        AND business_days.business_date BETWEEN ? AND ?
        AND stock_items.count_type = 'number'
        AND day_results.actual_qty IS NOT NULL
      ORDER BY business_days.business_date
      ''',
      [from, to],
    );
    final daysByItem = <int, List<UsagePoint>>{};
    for (final row in resultRows) {
      final id = row['stock_item_id'] as int;
      (daysByItem[id] ??= []).add(
        UsagePoint(
          date: row['business_date'] as String,
          used: (row['actual_qty'] as num).toDouble(),
          expected: (row['expected_qty'] as num?)?.toDouble(),
          gap: (row['gap'] as num?)?.toDouble(),
        ),
      );
    }

    final checkRows = await _db.rawQuery(
      '''
      SELECT container_checks.*, business_days.business_date
      FROM container_checks
      JOIN business_days ON business_days.id = container_checks.day_id
      WHERE business_days.status = 'submitted'
        AND business_days.business_date BETWEEN ? AND ?
      ORDER BY business_days.business_date DESC, container_checks.id
      ''',
      [from, to],
    );

    final items = await _items({
      ...daysByItem.keys,
      for (final row in checkRows) row['stock_item_id'] as int,
    });
    final numberItems =
        [
          for (final item in items.values)
            if (daysByItem.containsKey(item.id)) item,
        ]..sort((a, b) {
          final byCategory = a.category.toLowerCase().compareTo(
            b.category.toLowerCase(),
          );
          if (byCategory != 0) return byCategory;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    // the map in the same order as the items, so the table keeps that order on a tie
    final orderedDays = {
      for (final item in numberItems) item.id!: daysByItem[item.id]!,
    };

    return Analytics(
      numberItems: numberItems,
      daysByItem: orderedDays,
      checks: [
        for (final row in checkRows)
          DatedCheck(
            date: row['business_date'] as String,
            check: CheckRow(
              item: items[row['stock_item_id']]!,
              containers: row['containers'] as int,
              containerTotal: (row['container_total'] as num).toDouble(),
              expectedSinceLast: (row['expected_since_last'] as num?)
                  ?.toDouble(),
              sinceDate: row['since_date'] as String,
            ),
          ),
      ],
      noRecipe: await _noRecipe(from, to),
    );
  }

  // the stock items with these ids, archived ones too
  Future<Map<int, StockItem>> _items(Set<int> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _db.query(
      'stock_items',
      where: 'id IN (${List.filled(ids.length, '?').join(', ')})',
      whereArgs: ids.toList(),
    );
    return {for (final row in rows) row['id'] as int: StockItem.fromRow(row)};
  }

  // menu items ordered with no recipe on the day they were ordered, same rule as the daily report (rule 6)
  // the recipe check uses the lines active at each day's submitted_at (rule 12)
  Future<List<NoRecipeEntry>> _noRecipe(String from, String to) async {
    final rows = await _db.rawQuery(
      '''
      SELECT menu_items.name, COUNT(DISTINCT business_days.id) AS days
      FROM tally_lines
      JOIN business_days ON business_days.id = tally_lines.day_id
      JOIN menu_items ON menu_items.id = tally_lines.menu_item_id
      WHERE business_days.status = 'submitted'
        AND business_days.business_date BETWEEN ? AND ?
        AND tally_lines.qty > 0
        AND menu_items.no_stock = 0
        AND NOT EXISTS (
          SELECT 1 FROM recipe_lines
          WHERE recipe_lines.menu_item_id = menu_items.id
            AND recipe_lines.created_at <= business_days.submitted_at
            AND (recipe_lines.archived_at IS NULL
                 OR recipe_lines.archived_at > business_days.submitted_at)
        )
      GROUP BY menu_items.id
      ORDER BY menu_items.name COLLATE NOCASE
      ''',
      [from, to],
    );
    return [
      for (final row in rows)
        NoRecipeEntry(name: row['name'] as String, days: row['days'] as int),
    ];
  }
}
