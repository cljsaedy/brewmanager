import '../logic/audit_math.dart';
import '../models/audit_batch.dart';
import 'batch_repository.dart';
import 'database_helper.dart';

/// the closing stock count, loading what needs counting and writing the corrections back
class ReconciliationRepository {
  ReconciliationRepository({DatabaseHelper? helper, BatchRepository? batches})
      : _helper = helper ?? DatabaseHelper.instance,
        _batches = batches ?? BatchRepository();

  final DatabaseHelper _helper;
  final BatchRepository _batches;

  /// every batch that needs counting, with its hidden theoretical and starting controls
  ///
  /// depleted batches are included because the empty containers are still on the shelf
  /// and a sealed count on one is how unrecorded receiving gets spotted
  Future<List<AuditBatch>> loadBatchesToAudit() async {
    final db = await _helper.database;
    final batches = await _batches.getAllWithIngredient(includeDepleted: true);

    // containers declared lost per batch, so the sealed ceiling can be worked out
    final lossRows = await db.rawQuery('''
      SELECT batch_id, SUM(containers_lost) AS lost
      FROM loss_events
      GROUP BY batch_id
    ''');
    final lostByBatch = {
      for (final row in lossRows)
        row['batch_id'] as int: (row['lost'] as num).toInt(),
    };

    // the most recent counted quantity per batch, what the controls start on
    final lastRows = await db.rawQuery('''
      SELECT r.batch_id, r.audited_quantity
      FROM reconciliation_logs r
      JOIN (
        SELECT batch_id, MAX(reconciliation_id) AS newest
        FROM reconciliation_logs
        GROUP BY batch_id
      ) newest ON newest.batch_id = r.batch_id
               AND newest.newest = r.reconciliation_id
    ''');
    final lastAuditedByBatch = {
      for (final row in lastRows)
        row['batch_id'] as int: (row['audited_quantity'] as num).toDouble(),
    };

    return batches.map((b) {
      final batchId = b.batch.batchId;
      return AuditBatch(
        batch: b,
        // read now, kept out of the UI until the count is submitted
        theoreticalQuantity: b.batch.quantityRemaining,
        containersPossible: AuditMath.containersPossible(
          containersReceived: b.batch.containersReceived,
          containersLost: lostByBatch[batchId] ?? 0,
        ),
        startingEntry: AuditMath.startingEntry(
          lastAuditedByBatch[batchId],
          b.batch.containerCapacity,
        ),
      );
    }).toList();
  }

  /// writes the count back, this is the step that makes the inventory self correcting
  ///
  /// a system that measures drift but doesn't correct it is just a report, so the
  /// counted quantity REPLACES the computed one rather than being logged beside it
  Future<void> submitAudit({
    required int shiftId,
    required List<AuditResult> results,
  }) async {
    final db = await _helper.database;

    // one transaction, every batch is corrected or none is
    await db.transaction((txn) async {
      for (final result in results) {
        await txn.insert('reconciliation_logs', {
          'shift_id': shiftId,
          'batch_id': result.auditBatch.batchId,
          'theoretical_quantity': result.auditBatch.theoreticalQuantity,
          'audited_quantity': result.auditedQuantity,
          'variance': result.variance,
          'variance_type': result.varianceType,
        });

        // THE WRITE-BACK, the shelf is the truth so the record is set to what was counted
        final updates = <String, Object?>{
          'quantity_remaining': result.auditedQuantity,
        };

        // an impossible sealed count means stock arrived without being recorded,
        // so the container count is raised to match what was actually found
        if (result.varianceType == VarianceType.unrecordedReceiving) {
          updates['containers_received'] = result.entry.sealedCount;
        }

        await txn.update(
          'inventory_batches',
          updates,
          where: 'batch_id = ?',
          whereArgs: [result.auditBatch.batchId],
        );
      }
    });
  }
}
