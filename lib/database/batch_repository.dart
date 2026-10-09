import 'package:sqflite/sqflite.dart';

import '../models/inventory_batch.dart';
import 'database_helper.dart';

/// all db access for the inventory_batches table
class BatchRepository {
  BatchRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// batches with their ingredient name, soonest expiry first
  ///
  /// [includeDepleted] brings in batches at zero, the expiry matrix wants them since
  /// empty containers are still physically on the shelf and get counted at the audit
  Future<List<BatchWithIngredient>> getAllWithIngredient({
    bool includeDepleted = false,
  }) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT b.*, i.name AS ingredient_name, i.unit_of_measure
      FROM inventory_batches b
      JOIN ingredients i ON i.ingredient_id = b.ingredient_id
      ${includeDepleted ? '' : 'WHERE b.quantity_remaining > 0'}
      ORDER BY b.expiry_date, i.name COLLATE NOCASE
    ''');
    return rows.map(BatchWithIngredient.fromMap).toList();
  }

  /// saves a whole delivery at once, merging into an existing batch when one matches
  Future<void> insertAll(List<NewBatch> batches) async {
    final db = await _helper.database;
    final now = DateTime.now().toIso8601String();

    // one transaction so a crash halfway can't leave half a delivery recorded
    await db.transaction((txn) async {
      for (final b in batches) {
        final existing = await _findMatching(txn, b);
        if (existing == null) {
          await _insertNew(txn, b, now);
        } else {
          await _mergeInto(txn, existing, b);
        }
      }
    });
  }

  /// a batch is defined by ingredient + expiry + container size (rule 1), if a row with all three exists it's the same batch
  /// two rows for the same physical carton would make the audit impossible since the barista can't tell which carton belongs to which row
  Future<InventoryBatch?> _findMatching(DatabaseExecutor txn, NewBatch b) async {
    final rows = await txn.query(
      'inventory_batches',
      where: 'ingredient_id = ? AND expiry_date = ? AND container_capacity = ?',
      whereArgs: [b.ingredientId, formatDate(b.expiryDate), b.containerCapacity],
      limit: 1,
    );
    return rows.isEmpty ? null : InventoryBatch.fromMap(rows.first);
  }

  Future<void> _insertNew(DatabaseExecutor txn, NewBatch b, String now) async {
    await txn.insert('inventory_batches', {
      'ingredient_id': b.ingredientId,
      'expiry_date': formatDate(b.expiryDate),
      'container_capacity': b.containerCapacity,
      'containers_received': b.containersReceived,
      // starting stock, sales draw this down
      'quantity_remaining': b.totalQuantity,
      'received_at': now,
    });
  }

  /// adds the new containers onto the existing row, received_at stays as the first delivery
  Future<void> _mergeInto(
    DatabaseExecutor txn,
    InventoryBatch existing,
    NewBatch b,
  ) async {
    await txn.update(
      'inventory_batches',
      {
        'containers_received':
            existing.containersReceived + b.containersReceived,
        'quantity_remaining': existing.quantityRemaining + b.totalQuantity,
      },
      where: 'batch_id = ?',
      whereArgs: [existing.batchId],
    );
  }
}
