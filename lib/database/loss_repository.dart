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

  /// deducts the lost containers from the batch and logs the event, returns how much was deducted
  Future<double> declareContainerLost({
    required BatchWithIngredient batch,
    required int containersLost,
    required int userId,
  }) async {
    final db = await _helper.database;
    final shiftId = await _shifts.getOrCreateOpenShift(userId);

    // deducts containers, not the whole batch, losing 1 of 3 cartons only costs one carton
    final wanted = containersLost * batch.batch.containerCapacity;
    // a part used container can't lose more than what was actually in it, so never go below zero
    final deducted =
        wanted > batch.batch.quantityRemaining ? batch.batch.quantityRemaining : wanted;

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
