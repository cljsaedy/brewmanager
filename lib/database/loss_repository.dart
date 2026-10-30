import '../models/declared_loss.dart';
import '../models/inventory_batch.dart';
import 'database_helper.dart';
import 'shift_repository.dart';

/// db access for loss_events, declared losses like a dropped bottle
///
/// kept separate from unexplained variance at the audit so the loss chart can tell
/// a known incident from mystery drift
class LossRepository {
  LossRepository({DatabaseHelper? helper, ShiftRepository? shifts})
      : _helper = helper ?? DatabaseHelper.instance,
        _shifts = shifts ?? ShiftRepository();

  final DatabaseHelper _helper;
  final ShiftRepository _shifts;

  /// losses recorded recently, newest first, so a mistake can be found and undone
  Future<List<DeclaredLoss>> getRecent({int limit = 30}) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT l.*, i.name AS ingredient_name, i.unit_of_measure,
             b.container_capacity, u.name AS recorded_by
      FROM loss_events l
      JOIN inventory_batches b ON b.batch_id = l.batch_id
      JOIN ingredients i ON i.ingredient_id = b.ingredient_id
      JOIN shift_sessions s ON s.shift_id = l.shift_id
      JOIN users u ON u.user_id = s.user_id
      ORDER BY l.recorded_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(DeclaredLoss.fromMap).toList();
  }

  /// reverses a loss that was recorded by mistake
  ///
  /// puts the quantity back and removes the row outright, unlike a voided sale
  /// which is kept and flagged
  ///
  /// a sale is a record of money changing hands so it has to stay, a loss that
  /// never happened is not a record of anything, and leaving a flagged row would
  /// mean the loss chart has to know to skip it
  Future<void> undoLoss(DeclaredLoss loss) async {
    final db = await _helper.database;

    // one transaction, the stock going back and the row going away belong together
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE inventory_batches SET quantity_remaining = quantity_remaining + ? '
        'WHERE batch_id = ?',
        [loss.quantityDeducted, loss.batchId],
      );

      await txn.delete(
        'loss_events',
        where: 'loss_event_id = ?',
        whereArgs: [loss.lossEventId],
      );
    });
  }

  /// deducts a loss from the batch and logs the event, returns how much was deducted
  ///
  /// takes the containers and the quantity separately because they are not the
  /// same thing: losing the opened carton is one container but only what was
  /// left in it, while losing a sealed one is one container and a full capacity
  ///
  /// assuming a full container either way would delete stock that is still on
  /// the shelf, and that phantom shortfall would come back as a surplus at the
  /// next count, which is exactly the drift this system exists to remove
  Future<double> declareContainerLost({
    required BatchWithIngredient batch,
    required int containersLost,
    required double quantityLost,
    required int userId,
  }) async {
    final db = await _helper.database;
    final shiftId = await _shifts.getOrCreateOpenShift(userId);

    // can't lose more than the batch holds, whatever was passed in
    final deducted = quantityLost > batch.batch.quantityRemaining
        ? batch.batch.quantityRemaining
        : quantityLost;

    // one transaction, the stock change and its reason must land together or not at all
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE inventory_batches SET quantity_remaining = quantity_remaining - ? '
        'WHERE batch_id = ?',
        [deducted, batch.batch.batchId],
      );

      // containers_received is left alone on purpose, it means "how many were received"
      // increment 4's audit works out the sealed ceiling as containers_received minus losses logged here
      await txn.insert('loss_events', {
        'shift_id': shiftId,
        'batch_id': batch.batch.batchId,
        'containers_lost': containersLost,
        'quantity_deducted': deducted,
        'recorded_at': DateTime.now().toIso8601String(),
      });
    });

    return deducted;
  }
}
