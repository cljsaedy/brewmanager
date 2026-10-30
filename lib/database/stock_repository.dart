import '../logic/fefo_engine.dart';
import '../models/inventory_batch.dart' show formatDate;
import 'database_helper.dart';

/// read only access to batch stock, shaped as what the fefo engine takes as input
///
/// "usable" throughout here means a batch that still holds something AND has not
/// passed its expiry date, which is the only stock a sale may draw from
///
/// expired stock still exists on the shelf and still gets counted at the closing
/// audit, it is simply not sellable, so it is reported separately rather than
/// quietly folded into the totals
class StockRepository {
  StockRepository({DatabaseHelper? helper})
    : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// every usable batch grouped by ingredient
  ///
  /// one query instead of one per menu item on the pos grid
  ///
  /// expiry_date is YYYY-MM-DD text, which compares correctly as a string, and
  /// a batch expiring today is still usable today
  Future<Map<int, List<BatchStock>>> getAllBatchStock({
    DateTime? today,
  }) async {
    final cutoff = formatDate(today ?? DateTime.now());
    return _groupedWhere('quantity_remaining > 0 AND expiry_date >= ?', [
      cutoff,
    ]);
  }

  /// every batch that still holds stock but has gone past its expiry date
  ///
  /// the till uses this to say an item is unavailable because its ingredient
  /// expired, rather than reporting it as simply out of stock while the stock
  /// screen plainly shows plenty of it
  Future<Map<int, double>> getExpiredTotals({DateTime? today}) async {
    final cutoff = formatDate(today ?? DateTime.now());
    final grouped = await _groupedWhere(
      'quantity_remaining > 0 AND expiry_date < ?',
      [cutoff],
    );

    return {
      for (final entry in grouped.entries)
        entry.key: entry.value.fold<double>(
          0,
          (sum, b) => sum + b.quantityRemaining,
        ),
    };
  }

  Future<Map<int, List<BatchStock>>> _groupedWhere(
    String where,
    List<Object?> args,
  ) async {
    final db = await _helper.database;
    final rows = await db.query(
      'inventory_batches',
      columns: [
        'batch_id',
        'ingredient_id',
        'expiry_date',
        'quantity_remaining',
      ],
      where: where,
      whereArgs: args,
    );

    final grouped = <int, List<BatchStock>>{};
    for (final row in rows) {
      final ingredientId = row['ingredient_id'] as int;
      // putIfAbsent makes the list on first sight of that ingredient
      grouped.putIfAbsent(ingredientId, () => []).add(_toBatchStock(row));
    }
    return grouped;
  }

  BatchStock _toBatchStock(Map<String, Object?> row) {
    return BatchStock(
      batchId: row['batch_id'] as int,
      expiryDate: row['expiry_date'] as String,
      quantityRemaining: (row['quantity_remaining'] as num).toDouble(),
    );
  }
}
