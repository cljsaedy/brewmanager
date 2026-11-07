import '../logic/count_math.dart';
import 'stock_item.dart';

// one row of the business_days table
class BusinessDay {
  const BusinessDay({
    required this.id,
    required this.businessDate,
    required this.status,
    this.dayNote,
  });

  final int id;
  // YYYY-MM-DD text, the date the day is counted for, not always today (rule 5)
  final String businessDate;
  // the one optional note about the whole day (rule 9)
  final String? dayNote;
  // draft, submitted or closed
  final String status;

  // the business date as a DateTime, for screens that show it like "Sat, Oct 31"
  DateTime get date => DateTime.parse(businessDate);

  factory BusinessDay.fromRow(Map<String, Object?> row) {
    return BusinessDay(
      id: row['id'] as int,
      businessDate: row['business_date'] as String,
      status: row['status'] as String,
      dayNote: row['day_note'] as String?,
    );
  }
}

// one row of the count_lines table = one stock item on one business day
// every amount is in the stock item's base unit
class CountLine {
  const CountLine({
    required this.id,
    required this.dayId,
    required this.stockItemId,
    required this.startQty,
    required this.startIsExact,
    required this.inQty,
    required this.outCount,
    required this.sealed,
    required this.level,
    required this.exactQty,
    required this.endQty,
    required this.endIsExact,
    required this.touched,
    required this.isOpening,
    required this.note,
  });

  final int id;
  final int dayId;
  final int stockItemId;
  // the End of the last submitted count
  final double startQty;
  // keeps yesterday's exact / estimated flag
  final bool startIsExact;
  // restocks today
  final double inQty;
  // containers finished today
  final int outCount;
  // these 3 are null for number items, the number is endQty
  final int? sealed;
  final double? level;
  // typed exact amount for the opened container, replaces the level
  final double? exactQty;
  final double endQty;
  final bool endIsExact;
  // true once the barista changed this line today
  final bool touched;
  // true when this is the item's opening count, it sets the starting stock only (rule 3)
  final bool isOpening;
  final String? note;

  factory CountLine.fromRow(Map<String, Object?> row) {
    return CountLine(
      id: row['id'] as int,
      dayId: row['day_id'] as int,
      stockItemId: row['stock_item_id'] as int,
      // sqlite can give back a whole number as int, so read it as num then make it double
      startQty: (row['start_qty'] as num).toDouble(),
      startIsExact: row['start_is_exact'] == 1,
      inQty: (row['in_qty'] as num).toDouble(),
      outCount: row['out_count'] as int,
      sealed: row['sealed'] as int?,
      level: (row['level'] as num?)?.toDouble(),
      exactQty: (row['exact_qty'] as num?)?.toDouble(),
      endQty: (row['end_qty'] as num).toDouble(),
      endIsExact: row['end_is_exact'] == 1,
      touched: row['touched'] == 1,
      isOpening: row['is_opening'] == 1,
      note: row['note'] as String?,
    );
  }
}

// one restock from the stock_events table
class Restock {
  const Restock({required this.id, required this.qty, required this.time});

  final int id;
  // in base units
  final double qty;
  // on the tablet's clock, the db keeps it in utc
  final DateTime time;

  factory Restock.fromRow(Map<String, Object?> row) {
    return Restock(
      id: row['id'] as int,
      qty: (row['qty'] as num).toDouble(),
      time: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}

// a count line with its stock item, what the count tab needs for one row
class CountRow {
  const CountRow({
    required this.line,
    required this.item,
    this.restocks = const [],
    this.usedToday = false,
  });

  final CountLine line;
  final StockItem item;
  // today's restocks, oldest first
  final List<Restock> restocks;
  // true when a recipe of a menu item in today's tally uses this item
  final bool usedToday;

  // true when this row gets the double check badge
  // used today and not counted yet, it leaves once the barista touches the count
  bool get needsDoubleCheck => usedToday && !line.touched;

  // true when this row gets the restock recommended badge (rule 8)
  bool get restockRecommended {
    return isAtLowLevel(
      end: line.endQty,
      lowMode: item.lowMode,
      lowValue: item.lowValue,
      containerSize: item.containerSize,
    );
  }

  // true when this row has at least 1 badge to show
  bool get hasBadges =>
      needsDoubleCheck || line.isOpening || restockRecommended;
}

// the draft day with all its rows, ordered by category then name
class DraftDay {
  const DraftDay({required this.day, required this.rows});

  final BusinessDay day;
  final List<CountRow> rows;
}
