import 'package:sqflite/sqflite.dart';

import '../report/daily_report.dart';
import 'count_line.dart';
import 'history_store.dart';

// reads a submitted day into a DailyReport (rule 10)
// takes a DatabaseExecutor so submit can call it inside its own transaction
// it only reads what submit and corrections saved, it never works numbers out itself
class ReportStore {
  ReportStore(this._db);

  final DatabaseExecutor _db;

  Future<DailyReport> load(int dayId) async {
    // the day, the count rows (only items with results, by category then name) and the tally
    final detail = await HistoryStore(_db).detail(dayId);
    final day = detail.day;

    final resultRows = await _db.query(
      'day_results',
      where: 'day_id = ?',
      whereArgs: [dayId],
    );
    final results = {
      for (final row in resultRows) row['stock_item_id'] as int: row,
    };
    final usage = [
      for (final countRow in detail.rows)
        _usageRow(countRow, results[countRow.item.id]!),
    ];
    final items = {for (final row in usage) row.item.id!: row.item};

    final checkRows = await _db.query(
      'container_checks',
      where: 'day_id = ?',
      whereArgs: [dayId],
    );
    final checks = [
      for (final row in checkRows)
        CheckRow(
          item: items[row['stock_item_id']]!,
          containers: row['containers'] as int,
          containerTotal: (row['container_total'] as num).toDouble(),
          expectedSinceLast: (row['expected_since_last'] as num?)?.toDouble(),
          sinceDate: row['since_date'] as String,
        ),
    ];
    // same order as the tables
    final order = [for (final row in usage) row.item.id];
    checks.sort(
      (a, b) => order.indexOf(a.item.id).compareTo(order.indexOf(b.item.id)),
    );

    return DailyReport(
      day: day,
      closedDates: await _closedDates(day.businessDate),
      usage: usage,
      checks: checks,
      noRecipe: await _noRecipe(dayId, day.submittedAt!),
      tally: detail.tally,
    );
  }

  UsageRow _usageRow(CountRow countRow, Map<String, Object?> result) {
    return UsageRow(
      item: countRow.item,
      line: countRow.line,
      expected: (result['expected_qty'] as num?)?.toDouble(),
      actual: (result['actual_qty'] as num?)?.toDouble(),
      actualIsExact: result['actual_is_exact'] == 1,
      gap: (result['gap'] as num?)?.toDouble(),
      restock: result['restock_flag'] == 1,
    );
  }

  // the closed days between the submitted day before this one and this day
  Future<List<String>> _closedDates(String date) async {
    final before = await _db.rawQuery(
      '''
      SELECT MAX(business_date) AS date FROM business_days
      WHERE status = 'submitted' AND business_date < ?
      ''',
      [date],
    );
    // no submitted day before = this is the first one, every closed day before it counts
    final after = before.first['date'] as String? ?? '';
    final rows = await _db.query(
      'business_days',
      columns: ['business_date'],
      where: "status = 'closed' AND business_date > ? AND business_date < ?",
      whereArgs: [after, date],
      orderBy: 'business_date',
    );
    return [for (final row in rows) row['business_date'] as String];
  }

  // tallied menu items that had no recipe when the day was submitted (rule 6)
  // the recipe check uses the lines active at submitted_at (rule 12), so a recipe added later
  // doesnt change an old report
  // no_stock items are left out, they need no recipe
  Future<List<String>> _noRecipe(int dayId, String submittedAt) async {
    final rows = await _db.rawQuery(
      '''
      SELECT menu_items.name
      FROM tally_lines
      JOIN menu_items ON menu_items.id = tally_lines.menu_item_id
      WHERE tally_lines.day_id = ?
        AND tally_lines.qty > 0
        AND menu_items.no_stock = 0
        AND NOT EXISTS (
          SELECT 1 FROM recipe_lines
          WHERE recipe_lines.menu_item_id = menu_items.id
            AND recipe_lines.created_at <= ?
            AND (recipe_lines.archived_at IS NULL
                 OR recipe_lines.archived_at > ?)
        )
      ORDER BY menu_items.name COLLATE NOCASE
      ''',
      [dayId, submittedAt, submittedAt],
    );
    return [for (final row in rows) row['name'] as String];
  }
}
