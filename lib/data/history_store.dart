import 'package:sqflite/sqflite.dart';

import 'count_line.dart';
import 'menu_item.dart';
import 'stock_item.dart';
import 'tally_store.dart';

// one past day with everything the history tab shows
// no expected numbers in here, history is on the barista side
class HistoryDetail {
  const HistoryDetail({
    required this.day,
    required this.rows,
    required this.tally,
  });

  final BusinessDay day;
  // the count lines, by category then name, empty for a closed day
  final List<CountRow> rows;
  // the menu items made that day, by category then name
  final List<TallyRow> tally;
}

// reads the submitted and closed days for the history tab, it never changes anything
class HistoryStore {
  // the db or a transaction, a correction reads the day inside its own transaction
  HistoryStore(this._db);

  final DatabaseExecutor _db;

  // the submitted and closed days, newest first, the draft is not history yet
  Future<List<BusinessDay>> days() async {
    final rows = await _db.query(
      'business_days',
      where: "status IN ('submitted', 'closed')",
      orderBy: 'business_date DESC',
    );
    return [for (final row in rows) BusinessDay.fromRow(row)];
  }

  // one day with its count lines and tally
  Future<HistoryDetail> detail(int dayId) async {
    final dayRows = await _db.query(
      'business_days',
      where: 'id = ?',
      whereArgs: [dayId],
    );

    return HistoryDetail(
      day: BusinessDay.fromRow(dayRows.first),
      rows: await _countRows(dayId),
      tally: await _tally(dayId),
    );
  }

  // only lines that got results at submit, those are the items the barista could see that day
  // an item archived during that day was hidden, so it stays hidden here too
  // archived items still come, a past day keeps every item it had (rule 12)
  // only the day_results row is checked to be there, none of its numbers are read
  Future<List<CountRow>> _countRows(int dayId) async {
    final lineRows = await _db.rawQuery(
      '''
      SELECT count_lines.* FROM count_lines
      WHERE count_lines.day_id = ?
        AND EXISTS (
          SELECT 1 FROM day_results
          WHERE day_results.day_id = count_lines.day_id
            AND day_results.stock_item_id = count_lines.stock_item_id
        )
      ''',
      [dayId],
    );
    final itemRows = await _db.query(
      'stock_items',
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    final lines = {
      for (final row in lineRows)
        row['stock_item_id'] as int: CountLine.fromRow(row),
    };

    // going through the items keeps their order
    return [
      for (final itemRow in itemRows)
        if (lines[itemRow['id']] != null)
          CountRow(
            line: lines[itemRow['id']]!,
            item: StockItem.fromRow(itemRow),
          ),
    ];
  }

  // the menu items tallied that day, archived ones too
  Future<List<TallyRow>> _tally(int dayId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT menu_items.*, tally_lines.qty
      FROM tally_lines
      JOIN menu_items ON menu_items.id = tally_lines.menu_item_id
      WHERE tally_lines.day_id = ? AND tally_lines.qty > 0
      ORDER BY menu_items.category COLLATE NOCASE,
               menu_items.name COLLATE NOCASE
      ''',
      [dayId],
    );
    return [
      for (final row in rows)
        TallyRow(item: MenuItem.fromRow(row), qty: row['qty'] as int),
    ];
  }
}
