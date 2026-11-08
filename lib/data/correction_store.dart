import 'package:sqflite/sqflite.dart';

import '../logic/clock.dart';
import '../logic/correction_math.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import '../report/correction_email.dart';
import 'count_line.dart';
import 'history_store.dart';
import 'stock_item.dart';
import 'submit_store.dart';

// the new values for one count line, the screen sends every field and the store logs only what changed
// container items fill sealed, level and maybe exactQty, number items fill number
class CountFix {
  const CountFix({
    this.sealed,
    this.level,
    this.exactQty,
    this.number,
    required this.inQty,
    required this.outCount,
    this.note,
  });

  final int? sealed;
  final double? level;
  final double? exactQty;
  final double? number;
  // the day's restock total in base units
  final double inQty;
  // containers finished
  final int outCount;
  final String? note;
}

// fixes on the latest submitted day (rule 4)
// every fix: checks the day can still be corrected, logs each changed field with its reason,
// works out the day's numbers again and queues a short email to the owner
// all of it in 1 transaction, so a fix is never half saved
class CorrectionStore {
  CorrectionStore(this._db, {Clock clock = utcNow}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  // the only day that can be corrected: the newest submitted day
  // once the next day is submitted that one is newer, so the old one is final
  // null before the first submit
  Future<int?> correctableDayId() => _latestSubmitted(_db);

  Future<int?> _latestSubmitted(DatabaseExecutor db) async {
    final rows = await db.query(
      'business_days',
      columns: ['id'],
      where: "status = 'submitted'",
      orderBy: 'business_date DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  // checked again inside every fix, the screen could be open while the next day gets submitted
  Future<void> _checkCanCorrect(Transaction txn, int dayId) async {
    if (await _latestSubmitted(txn) != dayId) {
      throw StateError('Only the latest submitted day can be corrected');
    }
  }

  // every correction needs a reason, trimmed, never empty
  String _cleanReason(String reason) {
    final clean = reason.trim();
    if (clean.isEmpty) throw ArgumentError('A correction needs a reason');
    return clean;
  }

  // a note box: trimmed, empty = null, same as saveNote
  String? _cleanNote(String? note) {
    final clean = note?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  // fixes one count line, gives back false when nothing changed (nothing gets saved or sent then)
  Future<bool> correctCount(
    int dayId,
    int stockItemId,
    CountFix fix,
    String reason,
  ) {
    final why = _cleanReason(reason);

    return _db.transaction((txn) async {
      await _checkCanCorrect(txn, dayId);
      final item = await _stockItem(txn, stockItemId);
      final lineRows = await txn.query(
        'count_lines',
        where: 'day_id = ? AND stock_item_id = ?',
        whereArgs: [dayId, stockItemId],
      );
      final old = CountLine.fromRow(lineRows.first);

      // the new count fields, End only comes from them (rule 3)
      final isContainer = item.countType == CountType.container;
      final Map<String, Object?> count;
      if (isContainer) {
        count = {
          'sealed': fix.sealed!,
          'level': fix.level!,
          'exact_qty': fix.exactQty,
          'end_qty': containerEnd(
            sealed: fix.sealed!,
            containerSize: item.containerSize!,
            level: fix.level!,
            exactQty: fix.exactQty,
          ),
          'end_is_exact':
              containerIsExact(level: fix.level!, exactQty: fix.exactQty)
              ? 1
              : 0,
        };
      } else {
        count = {'end_qty': fix.number!, 'end_is_exact': 1};
      }
      final newEnd = count['end_qty'] as double;
      final newNote = _cleanNote(fix.note);

      // a count changed when End or any of its fields changed, even if End came out the same
      final countChanged = isContainer
          ? fix.sealed != old.sealed ||
                fix.level != old.level ||
                fix.exactQty != old.exactQty
          : newEnd != old.endQty;

      final changes = <CorrectionEntry>[
        if (countChanged) _countEntry('end', item, old.endQty, newEnd, why),
        if (fix.inQty != old.inQty)
          _countEntry('in', item, old.inQty, fix.inQty, why),
        if (fix.outCount != old.outCount)
          _entry(
            'count',
            'out',
            item.name,
            '${old.outCount}',
            '${fix.outCount}',
            why,
            item: item,
          ),
        if (newNote != old.note)
          _entry('count', 'note', item.name, old.note, newNote, why),
      ];
      if (changes.isEmpty) return false;

      await txn.update(
        'count_lines',
        {
          ...count,
          'in_qty': fix.inQty,
          'out_count': fix.outCount,
          'note': newNote,
        },
        where: 'id = ?',
        whereArgs: [old.id],
      );
      await _log(txn, dayId, old.id, changes);
      if (countChanged) {
        await _updateDraft(
          txn,
          item,
          end: newEnd,
          endIsExact: count['end_is_exact'] == 1,
          state: isContainer
              ? ContainerState(
                  sealed: fix.sealed!,
                  level: fix.level!,
                  exactQty: fix.exactQty,
                )
              : null,
        );
      }
      await _finish(txn, dayId, changes);
      return true;
    });
  }

  // sets how many of a menu item were made, a menu item not tallied that day can be added too
  // gives back false when the number is the same
  Future<bool> correctTally(int dayId, int menuItemId, int qty, String reason) {
    final why = _cleanReason(reason);
    if (qty < 0) throw ArgumentError('A tally cant go below 0');

    return _db.transaction((txn) async {
      await _checkCanCorrect(txn, dayId);
      // INSERT OR IGNORE = makes the line at 0 only if it isnt there yet, so there is a line id to log
      // a line taken to 0 stays at 0 so the log still points to it, every screen skips 0 lines
      await txn.rawInsert(
        'INSERT OR IGNORE INTO tally_lines (day_id, menu_item_id, qty) '
        'VALUES (?, ?, 0)',
        [dayId, menuItemId],
      );
      final lineRows = await txn.query(
        'tally_lines',
        where: 'day_id = ? AND menu_item_id = ?',
        whereArgs: [dayId, menuItemId],
      );
      final line = lineRows.first;
      final oldQty = line['qty'] as int;
      if (oldQty == qty) return false;

      final menuRows = await txn.query(
        'menu_items',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [menuItemId],
      );
      final changes = [
        _entry(
          'tally',
          'qty',
          menuRows.first['name'] as String,
          '$oldQty',
          '$qty',
          why,
        ),
      ];
      await txn.update(
        'tally_lines',
        {'qty': qty},
        where: 'id = ?',
        whereArgs: [line['id']],
      );
      await _log(txn, dayId, line['id'] as int, changes);
      await _finish(txn, dayId, changes);
      return true;
    });
  }

  // fixes the day note, gives back false when it is the same
  Future<bool> correctDayNote(int dayId, String note, String reason) {
    final why = _cleanReason(reason);
    final newNote = _cleanNote(note);

    return _db.transaction((txn) async {
      await _checkCanCorrect(txn, dayId);
      final dayRows = await txn.query(
        'business_days',
        where: 'id = ?',
        whereArgs: [dayId],
      );
      final oldNote = dayRows.first['day_note'] as String?;
      if (oldNote == newNote) return false;

      final changes = [
        _entry('day', 'day_note', 'Day note', oldNote, newNote, why),
      ];
      await txn.update(
        'business_days',
        {'day_note': newNote},
        where: 'id = ?',
        whereArgs: [dayId],
      );
      // line_id holds the day's id for a day note (see the corrections table)
      await _log(txn, dayId, dayId, changes);
      await _finish(txn, dayId, changes);
      return true;
    });
  }

  // the corrections of a day, oldest first, for the history tab
  Future<List<CorrectionEntry>> corrections(int dayId) async {
    final rows = await _db.query(
      'corrections',
      where: 'day_id = ?',
      whereArgs: [dayId],
      orderBy: 'id',
    );
    final entries = <CorrectionEntry>[];
    for (final row in rows) {
      final target = row['target'] as String;
      final lineId = row['line_id'] as int;
      StockItem? item;
      String name = 'Day note';
      if (target == 'count') {
        final lines = await _db.query(
          'count_lines',
          columns: ['stock_item_id'],
          where: 'id = ?',
          whereArgs: [lineId],
        );
        item = await _stockItem(_db, lines.first['stock_item_id'] as int);
        name = item.name;
      } else if (target == 'tally') {
        final menu = await _db.rawQuery(
          '''
          SELECT menu_items.name FROM tally_lines
          JOIN menu_items ON menu_items.id = tally_lines.menu_item_id
          WHERE tally_lines.id = ?
          ''',
          [lineId],
        );
        name = menu.first['name'] as String;
      }
      entries.add(
        CorrectionEntry(
          target: target,
          field: row['field'] as String,
          name: name,
          oldValue: row['old_value'] as String?,
          newValue: row['new_value'] as String?,
          reason: row['reason'] as String,
          correctedAt: row['corrected_at'] as String,
          item: item,
        ),
      );
    }
    return entries;
  }

  Future<StockItem> _stockItem(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      'stock_items',
      where: 'id = ?',
      whereArgs: [id],
    );
    return StockItem.fromRow(rows.first);
  }

  // an amount change of a count line, saved as plain base units
  CorrectionEntry _countEntry(
    String field,
    StockItem item,
    double oldAmount,
    double newAmount,
    String reason,
  ) {
    return _entry(
      'count',
      field,
      item.name,
      plainNumber(oldAmount),
      plainNumber(newAmount),
      reason,
      item: item,
    );
  }

  CorrectionEntry _entry(
    String target,
    String field,
    String name,
    String? oldValue,
    String? newValue,
    String reason, {
    StockItem? item,
  }) {
    return CorrectionEntry(
      target: target,
      field: field,
      name: name,
      oldValue: oldValue,
      newValue: newValue,
      reason: reason,
      correctedAt: _clock().toIso8601String(),
      item: item,
    );
  }

  // one corrections row per changed field, never overwrite silently
  Future<void> _log(
    Transaction txn,
    int dayId,
    int lineId,
    List<CorrectionEntry> changes,
  ) async {
    for (final change in changes) {
      await txn.insert('corrections', {
        'day_id': dayId,
        'target': change.target,
        'line_id': lineId,
        'field': change.field,
        'old_value': change.oldValue,
        'new_value': change.newValue,
        'reason': change.reason,
        'corrected_at': change.correctedAt,
      });
    }
  }

  // after every fix: the day's numbers again, then the email with the corrected count table
  Future<void> _finish(
    Transaction txn,
    int dayId,
    List<CorrectionEntry> changes,
  ) async {
    await SubmitStore(_db, clock: _clock).recalculate(txn, dayId);

    final detail = await HistoryStore(txn).detail(dayId);
    final date = detail.day.businessDate;
    await txn.insert('outbox', {
      'kind': 'correction',
      'day_id': dayId,
      'subject': correctionSubject(date),
      'html_body': correctionEmailHtml(
        date: date,
        changes: changes,
        rows: detail.rows,
      ),
      'created_at': _clock().toIso8601String(),
    });
  }

  // a corrected End is the next draft's Start (rule 4)
  // if the barista already counted the item in the draft, their End stays since it is a real count
  // if not, End gets rebuilt from the corrected values plus today's restocks and finished taps,
  // so none of them are lost (see replayDay)
  // nothing happens if there is no draft line yet (it will carry over the new End when it gets made)
  // or if the draft line is an opening count (its Start is always 0)
  Future<void> _updateDraft(
    Transaction txn,
    StockItem item, {
    required double end,
    required bool endIsExact,
    required ContainerState? state,
  }) async {
    final lineRows = await txn.rawQuery(
      '''
      SELECT count_lines.* FROM count_lines
      JOIN business_days ON business_days.id = count_lines.day_id
      WHERE business_days.status = 'draft' AND count_lines.stock_item_id = ?
      ''',
      [item.id],
    );
    if (lineRows.isEmpty) return;
    final line = CountLine.fromRow(lineRows.first);
    if (line.isOpening) return;

    final values = <String, Object?>{
      'start_qty': end,
      'start_is_exact': endIsExact ? 1 : 0,
    };

    if (!line.touched) {
      final eventRows = await txn.query(
        'stock_events',
        where: 'day_id = ? AND stock_item_id = ?',
        whereArgs: [line.dayId, item.id],
        orderBy: 'id',
      );
      final events = [
        for (final row in eventRows)
          DayEvent(
            isRestock: row['kind'] == 'in',
            qty: (row['qty'] as num).toDouble(),
          ),
      ];

      if (state == null) {
        values['end_qty'] = replayNumber(start: end, events: events);
        values['end_is_exact'] = 1;
      } else {
        final result = replayDay(
          start: state,
          events: events,
          containerSize: item.containerSize!,
        );
        final now = result.end;
        values.addAll({
          'sealed': now.sealed,
          'level': now.level,
          'exact_qty': now.exactQty,
          'end_qty': containerEnd(
            sealed: now.sealed,
            containerSize: item.containerSize!,
            level: now.level,
            exactQty: now.exactQty,
          ),
          'end_is_exact':
              containerIsExact(level: now.level, exactQty: now.exactQty)
              ? 1
              : 0,
        });

        // each finished tap gets its new "before" values so undo still works
        final outRows = eventRows.where((row) => row['kind'] == 'out');
        var i = 0;
        for (final row in outRows) {
          final before = result.beforeEachFinish[i++];
          await txn.update(
            'stock_events',
            {
              'prev_sealed': before.sealed,
              'prev_level': before.level,
              'prev_exact': before.exactQty,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    }

    await txn.update(
      'count_lines',
      values,
      where: 'id = ?',
      whereArgs: [line.id],
    );
  }
}
