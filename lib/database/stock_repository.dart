import '../logic/fefo_engine.dart';
import 'database_helper.dart';

/// read only access to batch stock, shaped as what the fefo engine takes as input
class StockRepository {
  StockRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// batches of one ingredient that still have stock, for a single deduction
  Future<List<BatchStock>> getBatchStockFor(int ingredientId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'inventory_batches',
      columns: ['batch_id', 'expiry_date', 'quantity_remaining'],
      where: 'ingredient_id = ? AND quantity_remaining > 0',
      whereArgs: [ingredientId],
    );
    return rows.map(_toBatchStock).toList();
  }

  /// every batch with stock grouped by ingredient, one query instead of one per menu item on the pos grid
  Future<Map<int, List<BatchStock>>> getAllBatchStock() async {
    final db = await _helper.database;
    final rows = await db.query(
      'inventory_batches',
      columns: [
        'batch_id',
        'ingredient_id',
        'expiry_date',
        'quantity_remaining',
      ],
      where: 'quantity_remaining > 0',
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
