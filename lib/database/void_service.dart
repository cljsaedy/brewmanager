import '../models/sale.dart';
import 'database_helper.dart';

/// thrown when the sale was already voided, stops stock being restored twice
class AlreadyVoidedException implements Exception {}

/// reverses a sale, putting each deducted amount back in the exact batch it came from
///
/// this is only possible because every deduction was written as its own row naming
/// its batch (rule 3), without those rows a reversal would have to guess which batch to credit
class VoidService {
  VoidService({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// marks the sale voided and restores stock, returns what went back where
  Future<List<RestoredBatch>> voidTransaction({
    required int transactionId,
    required int managerUserId,
  }) async {
    final db = await _helper.database;

    // one transaction so the void mark and the stock restore can't come apart
    return db.transaction((txn) async {
      // re-read inside the transaction, two taps could both have passed an earlier check
      final rows = await txn.query(
        'transactions',
        columns: ['is_voided'],
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) throw AlreadyVoidedException();
      if ((rows.first['is_voided'] as int) == 1) throw AlreadyVoidedException();

      // marked, never deleted, the sale stays in history as a voided sale
      await txn.update(
        'transactions',
        {'is_voided': 1, 'voided_by': managerUserId},
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      );

      // the deduction rows stay in place as the record of what happened,
      // is_voided on the parent is what tells reports to ignore them
      final deductions = await txn.rawQuery('''
        SELECT bd.batch_id, bd.quantity_deducted,
               i.name AS ingredient_name, i.unit_of_measure
        FROM batch_deductions bd
        JOIN inventory_batches b ON b.batch_id = bd.batch_id
        JOIN ingredients i ON i.ingredient_id = b.ingredient_id
        WHERE bd.transaction_id = ?
      ''', [transactionId]);

      final restored = <RestoredBatch>[];
      for (final row in deductions) {
        final batchId = row['batch_id'] as int;
        final quantity = (row['quantity_deducted'] as num).toDouble();

        // add it back to that exact batch, a depleted batch can come back above zero
        // which is right, the stock physically never left the shelf
        await txn.rawUpdate(
          'UPDATE inventory_batches SET quantity_remaining = quantity_remaining + ? '
          'WHERE batch_id = ?',
          [quantity, batchId],
        );

        restored.add(RestoredBatch(
          batchId: batchId,
          ingredientName: row['ingredient_name'] as String,
          quantity: quantity,
          unitOfMeasure: row['unit_of_measure'] as String,
        ));
      }

      return restored;
    });
  }
}
