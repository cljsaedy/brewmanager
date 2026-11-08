import 'package:sqflite/sqflite.dart';

import '../logic/business_day.dart';
import '../logic/clock.dart';
import '../logic/count_math.dart';
import '../logic/units.dart';
import '../logic/usage_math.dart';
import '../report/daily_email.dart';
import '../report/template_summary.dart';
import 'count_line.dart';
import 'report_store.dart';
import 'stock_item.dart';

// one IN or OUT event for the review
class ReviewEvent {
  const ReviewEvent({
    required this.item,
    required this.isRestock,
    required this.qty,
    required this.time,
  });

  final StockItem item;
  // true = a restock, false = a finished container
  final bool isRestock;
  // base units for a restock, 1 for a finished container
  final double qty;
  // on the tablet's clock
  final DateTime time;
}

// one item note for the review
class ReviewNote {
  const ReviewNote({required this.itemName, required this.note});

  final String itemName;
  final String note;
}

// what the review step shows before a submit, no expected numbers in here
class DayReview {
  const DayReview({
    required this.itemsChanged,
    required this.tallyTotal,
    required this.events,
    required this.notes,
    required this.dayNote,
    required this.doubleCheckItems,
    required this.openingItems,
    required this.noRecipeItems,
  });

  // items counted, restocked or finished today
  final int itemsChanged;
  // how many menu items were tallied today
  final int tallyTotal;
  // all of the day's IN and OUT events, oldest first
  final List<ReviewEvent> events;
  final List<ReviewNote> notes;
  final String? dayNote;

  // the 3 warnings, they never stop the submit
  // used today but not counted yet
  final List<String> doubleCheckItems;
  // opening count items not counted yet
  final List<String> openingItems;
  // tallied menu items with no recipe yet
  final List<String> noRecipeItems;

  bool get hasWarnings =>
      doubleCheckItems.isNotEmpty ||
      openingItems.isNotEmpty ||
      noRecipeItems.isNotEmpty;
}

// locks a day and saves its numbers (rule 4 and rule 5)
class SubmitStore {
  SubmitStore(this._db, {Clock clock = utcNow}) : _clock = clock;

  final Database _db;
  final Clock _clock;

  // gets the review of a draft day, draft = the day fresh from loadDraft
  Future<DayReview> review(DraftDay draft) async {
    final dayId = draft.day.id;
    final rows = draft.rows;
    final items = {for (final row in rows) row.item.id: row.item};

    // id as the 2nd sort so 2 events in the same moment stay in the order they were added
    final eventRows = await _db.query(
      'stock_events',
      where: 'day_id = ?',
      whereArgs: [dayId],
      orderBy: 'created_at, id',
    );
    final events = <ReviewEvent>[];
    for (final row in eventRows) {
      // an item archived during the day is hidden, so it has no row here
      final item = items[row['stock_item_id']];
      if (item == null) continue;
      events.add(
        ReviewEvent(
          item: item,
          isRestock: row['kind'] == 'in',
          qty: (row['qty'] as num).toDouble(),
          time: DateTime.parse(row['created_at'] as String).toLocal(),
        ),
      );
    }

    final tallyRows = await _db.rawQuery(
      'SELECT COALESCE(SUM(qty), 0) AS total FROM tally_lines WHERE day_id = ?',
      [dayId],
    );

    return DayReview(
      itemsChanged: rows
          .where(
            (row) =>
                row.line.touched || row.line.inQty > 0 || row.line.outCount > 0,
          )
          .length,
      tallyTotal: tallyRows.first['total'] as int,
      events: events,
      notes: [
        for (final row in rows)
          if (row.line.note != null)
            ReviewNote(itemName: row.item.name, note: row.line.note!),
      ],
      dayNote: draft.day.dayNote,
      doubleCheckItems: [
        for (final row in rows)
          if (row.needsDoubleCheck) row.item.name,
      ],
      openingItems: [
        for (final row in rows)
          if (row.line.isOpening && !row.line.touched) row.item.name,
      ],
      noRecipeItems: await _noRecipeItems(dayId),
    );
  }

  // tallied menu items with no active recipe line
  // no_stock items are left out, the owner said they have no recipe to compare (rule 6)
  Future<List<String>> _noRecipeItems(int dayId) async {
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
            AND recipe_lines.is_archived = 0
        )
      ORDER BY menu_items.name COLLATE NOCASE
      ''',
      [dayId],
    );
    return [for (final row in rows) row['name'] as String];
  }

  // the names of a submitted day's restock recommended items, for the submitted screen
  // only names are read, the expected numbers in day_results stay off the barista side
  Future<List<String>> restockItems(int dayId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT stock_items.name
      FROM day_results
      JOIN stock_items ON stock_items.id = day_results.stock_item_id
      WHERE day_results.day_id = ? AND day_results.restock_flag = 1
      ORDER BY stock_items.category COLLATE NOCASE,
               stock_items.name COLLATE NOCASE
      ''',
      [dayId],
    );
    return [for (final row in rows) row['name'] as String];
  }

  // submits a draft day, gives back false if it was not a draft anymore
  // date = the date the barista confirmed, it can only be the draft's date or later
  // skippedDaysOpen = the answer to "was the cafe open on those days?", only used when the date moved
  //
  // everything is in 1 transaction so a day is never half submitted, one error undoes all of it
  // a double tap cant submit twice: sqlite runs transactions one at a time,
  // so the 2nd one reads the status after the 1st finished and stops there
  // the next draft is not made here, it gets made on the next loadDraft like any new draft
  Future<bool> submit(
    int dayId, {
    required String date,
    bool skippedDaysOpen = true,
  }) {
    return _db.transaction((txn) async {
      final rows = await txn.query(
        'business_days',
        where: 'id = ?',
        whereArgs: [dayId],
      );
      final day = BusinessDay.fromRow(rows.first);
      if (day.status != 'draft') return false;

      final draftDate = day.businessDate;
      if (!canSubmitOn(draftDate: draftDate, chosenDate: date)) {
        throw ArgumentError('A business day cant go back: $date');
      }
      final skipped = skippedDates(draftDate: draftDate, chosenDate: date);
      final submittedAt = _clock().toIso8601String();

      // the date moves first so a closed day can take the draft's old date below
      await txn.update(
        'business_days',
        {
          'business_date': date,
          'status': 'submitted',
          'submitted_at': submittedAt,
          // open on the skipped days = this count covers all of them, like "covers Oct 29-30"
          'covers_from': skipped.isNotEmpty && skippedDaysOpen
              ? draftDate
              : null,
        },
        where: 'id = ?',
        whereArgs: [dayId],
      );
      if (!skippedDaysOpen) {
        for (final closedDate in skipped) {
          await txn.insert('business_days', {
            'business_date': closedDate,
            'status': 'closed',
          });
        }
      }

      await _saveResults(txn, dayId, date, submittedAt);

      // the opening count is done, so these items carry over normally from now on (rule 3)
      await txn.rawUpdate(
        '''
        UPDATE stock_items SET needs_opening_count = 0
        WHERE id IN (
          SELECT stock_item_id FROM count_lines
          WHERE day_id = ? AND is_opening = 1
        )
        ''',
        [dayId],
      );

      // the owner's daily report goes in the outbox in this same transaction (rule 10)
      // so a submitted day always has its email waiting, feature 9c sends it
      // the template summary for now, the ai one can take its place later (9b)
      await _queueDailyReport(txn, dayId, date, submittedAt);
      return true;
    });
  }

  // builds the daily report from the saved results and queues its email
  // summary_source says which summary went in, so the evaluation can count them
  Future<void> _queueDailyReport(
    Transaction txn,
    int dayId,
    String date,
    String createdAt,
  ) async {
    final report = await ReportStore(txn).load(dayId);
    await txn.insert('outbox', {
      'kind': 'daily',
      'day_id': dayId,
      'subject': dailySubject(date),
      'html_body': dailyEmailHtml(report, templateSummary(report)),
      'created_at': createdAt,
    });
    await txn.update(
      'business_days',
      {'summary_source': 'template'},
      where: 'id = ?',
      whereArgs: [dayId],
    );
  }

  // works out a submitted day's numbers again, a correction calls this inside its own transaction
  // it uses the recipes from when the day was submitted, not the ones now (rule 12)
  Future<void> recalculate(Transaction txn, int dayId) async {
    final rows = await txn.query(
      'business_days',
      where: 'id = ?',
      whereArgs: [dayId],
    );
    final day = BusinessDay.fromRow(rows.first);
    await _saveResults(txn, dayId, day.businessDate, day.submittedAt!);
  }

  // works out and saves the numbers of a day, the old ones get replaced
  // on its own since a correction has to do this again
  // only items still active get results, an item archived during the day was hidden from the barista
  Future<void> _saveResults(
    Transaction txn,
    int dayId,
    String date,
    String submittedAt,
  ) async {
    await txn.delete('day_results', where: 'day_id = ?', whereArgs: [dayId]);
    await txn.delete(
      'container_checks',
      where: 'day_id = ?',
      whereArgs: [dayId],
    );

    final lineRows = await txn.query(
      'count_lines',
      where: 'day_id = ?',
      whereArgs: [dayId],
    );
    final items = await _activeItems(txn);
    final inRecipe = await _recipeItemIds(txn, submittedAt);
    final uses = await _recipeUses(txn, dayId, submittedAt);

    for (final row in lineRows) {
      final line = CountLine.fromRow(row);
      final item = items[line.stockItemId];
      if (item == null) continue;

      final usage = dayUsage(
        start: line.startQty,
        startIsExact: line.startIsExact,
        inQty: line.inQty,
        end: line.endQty,
        endIsExact: line.endIsExact,
        isOpening: line.isOpening,
        inRecipe: inRecipe.contains(item.id),
        uses: uses[item.id] ?? const [],
        lowMode: item.lowMode,
        lowValue: item.lowValue,
        containerSize: item.containerSize,
      );
      await txn.insert('day_results', {
        'day_id': dayId,
        'stock_item_id': item.id,
        'expected_qty': usage.expected,
        'actual_qty': usage.actual,
        'actual_is_exact': usage.actualIsExact ? 1 : 0,
        'gap': usage.gap,
        'restock_flag': usage.restockFlag ? 1 : 0,
      });

      if (item.countType != CountType.container) continue;
      final check = containerCheck(
        today: date,
        containersFinished: line.outCount,
        isOpening: line.isOpening,
        containerSize: item.containerSize!,
        expectedToday: usage.expected,
        earlierDays: await _earlierDays(txn, item, date),
      );
      if (check == null) continue;
      await txn.insert('container_checks', {
        'day_id': dayId,
        'stock_item_id': item.id,
        'containers': check.containers,
        'container_total': check.containerTotal,
        'expected_since_last': check.expectedSinceLast,
        'since_date': check.sinceDate,
      });
    }
  }

  // the active stock items by id
  Future<Map<int, StockItem>> _activeItems(Transaction txn) async {
    final rows = await txn.query('stock_items', where: 'is_archived = 0');
    final items = [for (final row in rows) StockItem.fromRow(row)];
    return {for (final item in items) item.id!: item};
  }

  // the stock items in at least 1 recipe when the day was submitted
  // an item that is in one has expected 0 on a day nothing using it was tallied, others have no expected
  Future<Set<int>> _recipeItemIds(Transaction txn, String submittedAt) async {
    final rows = await txn.rawQuery(
      '''
      SELECT DISTINCT stock_item_id FROM recipe_lines
      WHERE created_at <= ? AND (archived_at IS NULL OR archived_at > ?)
      ''',
      [submittedAt, submittedAt],
    );
    return {for (final row in rows) row['stock_item_id'] as int};
  }

  // how the day's tally used each stock item, by stock item id
  // these are the recipe lines active when the day was submitted, not the ones active now (rule 12)
  // so redoing an old day after a recipe edit still gives that day's numbers
  Future<Map<int, List<RecipeUse>>> _recipeUses(
    Transaction txn,
    int dayId,
    String submittedAt,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT recipe_lines.stock_item_id, recipe_lines.amount, tally_lines.qty
      FROM tally_lines
      JOIN recipe_lines
        ON recipe_lines.menu_item_id = tally_lines.menu_item_id
      WHERE tally_lines.day_id = ?
        AND tally_lines.qty > 0
        AND recipe_lines.created_at <= ?
        AND (recipe_lines.archived_at IS NULL
             OR recipe_lines.archived_at > ?)
      ''',
      [dayId, submittedAt, submittedAt],
    );

    final uses = <int, List<RecipeUse>>{};
    for (final row in rows) {
      final use = RecipeUse(
        menuQty: row['qty'] as int,
        amount: (row['amount'] as num).toDouble(),
      );
      uses.putIfAbsent(row['stock_item_id'] as int, () => []).add(use);
    }
    return uses;
  }

  // the submitted days of an item before this date, what a container check looks back at
  // LEFT JOIN = a day with no results row still comes back, its expected is just null
  // the current container size is used for the opened amount, the past size is not saved
  Future<List<PastDay>> _earlierDays(
    Transaction txn,
    StockItem item,
    String date,
  ) async {
    final rows = await txn.rawQuery(
      '''
      SELECT business_days.business_date, day_results.expected_qty,
             count_lines.out_count, count_lines.is_opening,
             count_lines.level, count_lines.exact_qty
      FROM count_lines
      JOIN business_days ON business_days.id = count_lines.day_id
      LEFT JOIN day_results
        ON day_results.day_id = count_lines.day_id
        AND day_results.stock_item_id = count_lines.stock_item_id
      WHERE count_lines.stock_item_id = ?
        AND business_days.status = 'submitted'
        AND business_days.business_date < ?
      ''',
      [item.id, date],
    );

    return [
      for (final row in rows)
        PastDay(
          date: row['business_date'] as String,
          expected: (row['expected_qty'] as num?)?.toDouble(),
          containersFinished: row['out_count'] as int,
          isOpening: row['is_opening'] == 1,
          openedAmount: openedAmount(
            containerSize: item.containerSize!,
            level: (row['level'] as num?)?.toDouble() ?? levelNone,
            exactQty: (row['exact_qty'] as num?)?.toDouble(),
          ),
        ),
    ];
  }
}
