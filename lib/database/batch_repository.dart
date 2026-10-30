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
      SELECT b.*, i.name AS ingredient_name, i.unit_of_measure,
             u.name AS corrected_by_name
      FROM inventory_batches b
      JOIN ingredients i ON i.ingredient_id = b.ingredient_id
      -- left join, most batches were never corrected
      LEFT JOIN users u ON u.user_id = b.corrected_by
      ${includeDepleted ? '' : 'WHERE b.quantity_remaining > 0'}
      ORDER BY b.expiry_date, i.name COLLATE NOCASE
    ''');
    return rows.map(BatchWithIngredient.fromMap).toList();
  }

  /// container sizes this ingredient has arrived in before, most used first
  ///
  /// receiving offers these as shortcuts, retyping 1000 every delivery is slow and
  /// a mistyped capacity quietly breaks the fefo maths for that batch
  Future<List<double>> capacitiesUsedFor(int ingredientId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT container_capacity, COUNT(*) AS uses
      FROM inventory_batches
      WHERE ingredient_id = ?
      GROUP BY container_capacity
      ORDER BY uses DESC, container_capacity DESC
    ''', [ingredientId]);

    return rows
        .map((r) => (r['container_capacity'] as num).toDouble())
        .toList();
  }

  /// the existing batch a new one would be merged into, null when it would be new
  ///
  /// receiving shows this so the manager isn't surprised when adding stock leaves
  /// the number of batches unchanged
  Future<InventoryBatch?> findMatchingBatch(NewBatch batch) async {
    final db = await _helper.database;
    return _findMatching(db, batch);
  }

  /// corrects a batch that was recorded wrongly at receiving
  ///
  /// a mistyped container size or count has no other way out: declaring the
  /// difference as a loss would record stock that never existed as waste, and
  /// leaving it means the closing count reports a huge unexplained shortfall,
  /// either way the loss figures the study reports would be wrong
  ///
  /// deliberately writes nothing to reconciliation_logs, those rows are the
  /// accuracy evidence from blind physical counts and a manual correction is not
  /// a measurement, mixing them would contaminate the evaluation
  ///
  /// instead the batch row itself records who corrected it, when, and what the
  /// quantity was beforehand, following the transactions.voided_by pattern of
  /// keeping the actor on the affected row
  ///
  /// [previousQuantity] is the quantity as it stood before this correction
  Future<void> correctBatch({
    required int batchId,
    required String expiryDate,
    required double containerCapacity,
    required int containersReceived,
    required double quantityRemaining,
    required double previousQuantity,
    required int correctedBy,
  }) async {
    final db = await _helper.database;
    await db.update(
      'inventory_batches',
      {
        'expiry_date': expiryDate,
        'container_capacity': containerCapacity,
        'containers_received': containersReceived,
        // never let a correction push stock below zero
        'quantity_remaining': quantityRemaining < 0 ? 0 : quantityRemaining,
        // overwritten by a later correction, only the most recent is kept
        'corrected_by': correctedBy,
        'corrected_at': DateTime.now().toIso8601String(),
        'previous_quantity': previousQuantity,
      },
      where: 'batch_id = ?',
      whereArgs: [batchId],
    );
  }

  /// whether anything already points at this batch
  ///
  /// a batch that has been sold from, lost from or counted can still be
  /// corrected, but the manager should know the history exists first
  Future<bool> hasHistory(int batchId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM batch_deductions WHERE batch_id = ?) +
        (SELECT COUNT(*) FROM loss_events WHERE batch_id = ?) +
        (SELECT COUNT(*) FROM reconciliation_logs WHERE batch_id = ?) AS uses
    ''', [batchId, batchId, batchId]);

    return ((rows.first['uses'] as num?)?.toInt() ?? 0) > 0;
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
