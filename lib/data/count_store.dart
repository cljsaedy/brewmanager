import 'dart:math';

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../logic/clock.dart';
import '../logic/count_math.dart';
import '../logic/units.dart';
import 'count_line.dart';
import 'stock_item.dart';
import 'tally_store.dart';

// the draft day and its count lines (rule 3 and rule 5)
class CountStore {
  CountStore(this._db, {Clock clock = utcNow}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  // the tally of the same days, it uses this same db
  TallyStore get tally => TallyStore(_db);

  // gets the draft day ready and reads it, the count tab calls this every time it loads
  // transaction = the new day and all its lines get saved together or not at all
  Future<DraftDay> loadDraft() async {
    final dayId = await _db.transaction((txn) async {
      final id = await _draftDayId(txn);
      await _syncLines(txn, id);
      return id;
    });
    return _readDay(dayId);
  }

  // the id of the draft day, makes one if there is none
  // the date only moves when a day is submitted, so an old draft stays even after midnight (rule 5)
  Future<int> _draftDayId(Transaction txn) async {
    final drafts = await txn.query(
      'business_days',
      where: "status = 'draft'",
      limit: 1,
    );
    if (drafts.isNotEmpty) return drafts.first['id'] as int;

    return txn.insert('business_days', {'business_date': await _nextDate(txn)});
  }

  // saves a container item's count, every tap on sealed or opened comes here (autosave)
  // End only comes from these fields so it is worked out again here (rule 3)
  // touched = 1 even if the value stayed the same, the barista still looked at the item
  Future<void> saveContainerCount(
    CountRow row, {
    required int sealed,
    required double level,
    required double? exactQty,
  }) async {
    final values = _containerValues(
      row.item,
      sealed: sealed,
      level: level,
      exactQty: exactQty,
    );
    await _db.update(
      'count_lines',
      {...values, 'touched': 1},
      where: 'id = ?',
      whereArgs: [row.line.id],
    );
  }

  // saves a number item's count, for these items the number is the End (rule 2)
  // a typed number has no level guess in it so it is always exact
  Future<void> saveNumberCount(int lineId, double number) async {
    await _db.update(
      'count_lines',
      {'end_qty': number, 'end_is_exact': 1, 'touched': 1},
      where: 'id = ?',
      whereArgs: [lineId],
    );
  }

  // saves the item note, an empty box is saved as null (rule 9)
  // the line stays untouched since a note is not a count
  Future<void> saveNote(int lineId, String note) async {
    final clean = note.trim();
    await _db.update(
      'count_lines',
      {'note': clean.isEmpty ? null : clean},
      where: 'id = ?',
      whereArgs: [lineId],
    );
  }

  // saves the low-stock level the barista typed, it stays in the mode the owner picked (rule 8)
  // this changes the stock item and not the line, so it stays the same on the next days too
  Future<void> saveLowValue(int stockItemId, double value) async {
    await _db.update(
      'stock_items',
      {'low_value': value},
      where: 'id = ?',
      whereArgs: [stockItemId],
    );
  }

  // saves one restock, each one is its own event with a time (rule 3)
  // restocks arrive sealed so a container item gets them in Sealed, a number item in the number
  // the line stays untouched, a restock is not a count of the item
  // transaction = the event and the line get saved together or not at all
  // gives back the saved line so the panel can show the new number
  Future<CountLine> addRestock(CountRow row, double qty) {
    return _db.transaction((txn) async {
      await txn.insert('stock_events', {
        'day_id': row.line.dayId,
        'stock_item_id': row.item.id,
        'kind': 'in',
        'qty': qty,
        'created_at': _clock().toIso8601String(),
      });

      final line = await _readLine(txn, row.line.id);
      final item = row.item;
      final Map<String, Object?> count;
      if (item.countType == CountType.container) {
        count = _containerValues(
          item,
          sealed: line.sealed! + containersIn(qty, item.containerSize!),
          level: line.level ?? levelNone,
          exactQty: line.exactQty,
        );
      } else {
        count = {'end_qty': roundAmount(line.endQty + qty)};
      }
      return _saveRestockChange(txn, row, count);
    });
  }

  // removes one restock and takes it back out of Sealed or the number (rule 3)
  // it stops at 0, the barista could have used those containers already
  // nothing happens if the restock is already gone, like after a double tap
  Future<CountLine> removeRestock(CountRow row, Restock restock) {
    return _db.transaction((txn) async {
      final removed = await txn.delete(
        'stock_events',
        where: 'id = ?',
        whereArgs: [restock.id],
      );
      final line = await _readLine(txn, row.line.id);
      if (removed == 0) return line;

      final item = row.item;
      final Map<String, Object?> count;
      if (item.countType == CountType.container) {
        count = _containerValues(
          item,
          sealed: sealedAfterRemove(
            line.sealed!,
            containersIn(restock.qty, item.containerSize!),
          ),
          level: line.level ?? levelNone,
          exactQty: line.exactQty,
        );
      } else {
        count = {'end_qty': max(0.0, roundAmount(line.endQty - restock.qty))};
      }
      return _saveRestockChange(txn, row, count);
    });
  }

  // saves the new count fields and in_qty, in_qty is always the sum of the day's IN events
  Future<CountLine> _saveRestockChange(
    Transaction txn,
    CountRow row,
    Map<String, Object?> count,
  ) async {
    final sum = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(qty), 0) AS total FROM stock_events
      WHERE day_id = ? AND stock_item_id = ? AND kind = 'in'
      ''',
      [row.line.dayId, row.item.id],
    );
    await txn.update(
      'count_lines',
      {...count, 'in_qty': roundAmount((sum.first['total'] as num).toDouble())},
      where: 'id = ?',
      whereArgs: [row.line.id],
    );
    return _readLine(txn, row.line.id);
  }

  // one count line fresh from the db, an autosave before this could have changed it
  Future<CountLine> _readLine(Transaction txn, int lineId) async {
    final rows = await txn.query(
      'count_lines',
      where: 'id = ?',
      whereArgs: [lineId],
    );
    return CountLine.fromRow(rows.first);
  }

  // one tap on container finished (rule 3)
  // the values from before the tap go on the event so undo knows what this tap changed
  // the line stays untouched, the app filled in the new level, the barista did not count it
  // nothing happens if there is nothing to finish, the db is read again here so a fast second tap is caught too
  // transaction = the event and the line get saved together or not at all
  Future<void> finishContainer(CountRow row) {
    return _db.transaction((txn) async {
      final line = await _readLine(txn, row.line.id);
      final sealed = line.sealed!;
      final canFinish = canFinishContainer(
        sealed: sealed,
        level: line.level ?? levelNone,
        exactQty: line.exactQty,
      );
      if (!canFinish) return;

      await txn.insert('stock_events', {
        'day_id': row.line.dayId,
        'stock_item_id': row.item.id,
        'kind': 'out',
        'qty': 1,
        'prev_sealed': sealed,
        'prev_level': line.level ?? levelNone,
        'prev_exact': line.exactQty,
        'created_at': _clock().toIso8601String(),
      });

      final count = _containerValues(
        row.item,
        sealed: sealedAfterFinish(sealed),
        level: levelAfterFinish(sealed),
        exactQty: null,
      );
      await _saveFinishChange(txn, row, count);
    });
  }

  // removes the last finished event and reverses only what that tap did (rule 3)
  // it is not a snapshot, restocks and edits made after the tap are never lost:
  // sealed goes up by 1 only if the tap took one out
  // opened goes back only if it is still what the tap set, otherwise it stays
  // gives back the saved line so the panel can show the new values
  Future<CountLine> undoFinish(CountRow row) {
    return _db.transaction((txn) async {
      final events = await txn.query(
        'stock_events',
        where: "day_id = ? AND stock_item_id = ? AND kind = 'out'",
        whereArgs: [row.line.dayId, row.item.id],
        orderBy: 'id DESC',
        limit: 1,
      );
      final line = await _readLine(txn, row.line.id);
      if (events.isEmpty) return line;

      final last = events.first;
      await txn.delete(
        'stock_events',
        where: 'id = ?',
        whereArgs: [last['id']],
      );

      final sealedBefore = last['prev_sealed'] as int;
      final level = line.level ?? levelNone;
      final putOpenedBack = openedStillFromFinish(
        level: level,
        exactQty: line.exactQty,
        sealedBefore: sealedBefore,
      );
      final count = _containerValues(
        row.item,
        sealed: sealedAfterUndo(
          sealed: line.sealed!,
          sealedBefore: sealedBefore,
        ),
        level: putOpenedBack ? (last['prev_level'] as num).toDouble() : level,
        exactQty: putOpenedBack
            ? (last['prev_exact'] as num?)?.toDouble()
            : line.exactQty,
      );
      await _saveFinishChange(txn, row, count);
      return _readLine(txn, row.line.id);
    });
  }

  // saves the new count fields and out_count, out_count is always the number of the day's OUT events
  Future<void> _saveFinishChange(
    Transaction txn,
    CountRow row,
    Map<String, Object?> count,
  ) async {
    final total = await txn.rawQuery(
      '''
      SELECT COUNT(*) AS total FROM stock_events
      WHERE day_id = ? AND stock_item_id = ? AND kind = 'out'
      ''',
      [row.line.dayId, row.item.id],
    );
    await txn.update(
      'count_lines',
      {...count, 'out_count': total.first['total']},
      where: 'id = ?',
      whereArgs: [row.line.id],
    );
  }

  // the date of a new draft: the day after the last submitted or closed day
  // so a date never goes back or repeats (rule 5)
  // no days yet = today on the tablet, the first count date from the setup wizard comes in feature 11
  Future<String> _nextDate(Transaction txn) async {
    final rows = await txn.query(
      'business_days',
      columns: ['business_date'],
      orderBy: 'business_date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return _dateFormat.format(_clock().toLocal());

    final last = _dateFormat.parse(rows.first['business_date'] as String);
    // day + 1 in the constructor handles the end of a month, Oct 31 -> Nov 1
    return _dateFormat.format(DateTime(last.year, last.month, last.day + 1));
  }

  // makes sure the draft matches the stock items as they are right now
  // the owner can change them anytime, so this runs on every load
  Future<void> _syncLines(Transaction txn, int dayId) async {
    final itemRows = await txn.query('stock_items', where: 'is_archived = 0');
    final lineRows = await txn.query(
      'count_lines',
      where: 'day_id = ?',
      whereArgs: [dayId],
    );
    final lines = {
      for (final row in lineRows)
        row['stock_item_id'] as int: CountLine.fromRow(row),
    };

    for (final itemRow in itemRows) {
      final item = StockItem.fromRow(itemRow);
      final line = lines[item.id];
      if (line == null) {
        await _insertLine(txn, dayId, item);
      } else {
        await _refreshLine(txn, line, item);
      }
    }
  }

  // new line for an item, carried over from its last submitted count (rule 3)
  // never counted before or just restored = opening count, everything starts at 0
  Future<void> _insertLine(Transaction txn, int dayId, StockItem item) async {
    final lastRows = await txn.rawQuery(
      '''
      SELECT c.* FROM count_lines c
      JOIN business_days d ON d.id = c.day_id
      WHERE c.stock_item_id = ? AND d.status = 'submitted'
      ORDER BY d.business_date DESC
      LIMIT 1
      ''',
      [item.id],
    );
    // a restored item has old counts, but they are ignored on purpose
    final last = lastRows.isEmpty || item.needsOpeningCount
        ? null
        : CountLine.fromRow(lastRows.first);

    final values = <String, Object?>{
      'day_id': dayId,
      'stock_item_id': item.id,
      'is_opening': last == null ? 1 : 0,
      // Start keeps yesterday's flag since it is the same number
      'start_qty': last?.endQty ?? 0,
      'start_is_exact': (last?.endIsExact ?? true) ? 1 : 0,
    };

    if (item.countType == CountType.container) {
      // the panel opens showing what was there last night
      values.addAll(
        _containerValues(
          item,
          sealed: last?.sealed ?? 0,
          level: last?.level ?? levelNone,
          exactQty: last?.exactQty,
        ),
      );
    } else {
      values.addAll({'end_qty': last?.endQty ?? 0, 'end_is_exact': 1});
    }

    await txn.insert('count_lines', values);
  }

  // brings a line that already exists up to date with its stock item
  Future<void> _refreshLine(
    Transaction txn,
    CountLine line,
    StockItem item,
  ) async {
    final isContainer = item.countType == CountType.container;
    // sealed is only filled for container items, so a mismatch means the count type changed
    // only allowed while the item has no history (rule 1), so this draft is all there is to drop
    if (isContainer != (line.sealed != null)) {
      await txn.delete(
        'stock_events',
        where: 'day_id = ? AND stock_item_id = ?',
        whereArgs: [line.dayId, line.stockItemId],
      );
      await txn.update(
        'count_lines',
        {
          'in_qty': 0,
          'out_count': 0,
          'touched': 0,
          ..._blankCount(isContainer),
        },
        where: 'id = ?',
        whereArgs: [line.id],
      );
      return;
    }

    // restored after this line was made, so its carried Start is old, it turns into an opening count (rule 3)
    // a line the barista already worked on keeps its count since that is a real count
    if (item.needsOpeningCount && !line.isOpening) {
      final worked = line.touched || line.inQty > 0 || line.outCount > 0;
      await txn.update(
        'count_lines',
        {
          'is_opening': 1,
          'start_qty': 0,
          'start_is_exact': 1,
          if (!worked) ..._blankCount(isContainer),
        },
        where: 'id = ?',
        whereArgs: [line.id],
      );
      // the fields just went to 0, so nothing left to work out below
      if (!worked) return;
    }
    if (!isContainer) return;

    // container size can change anytime, End only comes from the count fields so work it out again
    final values = _containerValues(
      item,
      sealed: line.sealed!,
      level: line.level ?? levelNone,
      exactQty: line.exactQty,
    );
    if (values['end_qty'] != line.endQty) {
      await txn.update(
        'count_lines',
        {'end_qty': values['end_qty']},
        where: 'id = ?',
        whereArgs: [line.id],
      );
    }
  }

  // the count fields of a line with nothing counted yet
  Map<String, Object?> _blankCount(bool isContainer) {
    return {
      'sealed': isContainer ? 0 : null,
      'level': isContainer ? levelNone : null,
      'exact_qty': null,
      'end_qty': 0,
      'end_is_exact': 1,
    };
  }

  // the count fields of a container line, with the End and the flag worked out from them
  Map<String, Object?> _containerValues(
    StockItem item, {
    required int sealed,
    required double level,
    required double? exactQty,
  }) {
    return {
      'sealed': sealed,
      'level': level,
      'exact_qty': exactQty,
      'end_qty': containerEnd(
        sealed: sealed,
        containerSize: item.containerSize!,
        level: level,
        exactQty: exactQty,
      ),
      'end_is_exact': containerIsExact(level: level, exactQty: exactQty)
          ? 1
          : 0,
    };
  }

  // reads a day with its rows, active stock items only, by category then name ignoring case (rule 1)
  // an item archived during the day keeps its line but is hidden here
  Future<DraftDay> _readDay(int dayId) async {
    final dayRows = await _db.query(
      'business_days',
      where: 'id = ?',
      whereArgs: [dayId],
    );
    final lineRows = await _db.query(
      'count_lines',
      where: 'day_id = ?',
      whereArgs: [dayId],
    );
    final lines = {
      for (final row in lineRows)
        row['stock_item_id'] as int: CountLine.fromRow(row),
    };
    final itemRows = await _db.query(
      'stock_items',
      where: 'is_archived = 0',
      orderBy: 'category COLLATE NOCASE, name COLLATE NOCASE',
    );
    // id as the 2nd sort so 2 restocks in the same moment stay in the order they were added
    final restockRows = await _db.query(
      'stock_events',
      where: "day_id = ? AND kind = 'in'",
      whereArgs: [dayId],
      orderBy: 'created_at, id',
    );
    final restocks = <int, List<Restock>>{};
    for (final row in restockRows) {
      final itemId = row['stock_item_id'] as int;
      restocks.putIfAbsent(itemId, () => []).add(Restock.fromRow(row));
    }

    final rows = <CountRow>[];
    for (final itemRow in itemRows) {
      final item = StockItem.fromRow(itemRow);
      rows.add(
        CountRow(
          line: lines[item.id]!,
          item: item,
          restocks: restocks[item.id] ?? const [],
        ),
      );
    }
    return DraftDay(day: BusinessDay.fromRow(dayRows.first), rows: rows);
  }
}
