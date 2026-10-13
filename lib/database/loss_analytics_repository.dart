import '../models/loss_record.dart';
import 'database_helper.dart';

/// reads losses for the chart, from both places a loss can be recorded
class LossAnalyticsRepository {
  LossAnalyticsRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// every loss in the window, optionally narrowed to one ingredient
  ///
  /// two sources: declared losses from loss_events, and unexplained shortfalls from
  /// the closing counts, kept apart so the chart can tell a known incident from drift
  Future<List<LossRecord>> getLosses({
    required DateTime from,
    required DateTime to,
    int? ingredientId,
  }) async {
    final declared = await _getDeclaredLosses(from, to, ingredientId);
    final unexplained = await _getUnexplainedLosses(from, to, ingredientId);

    final all = [...declared, ...unexplained];
    all.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    return all;
  }

  Future<List<LossRecord>> _getDeclaredLosses(
    DateTime from,
    DateTime to,
    int? ingredientId,
  ) async {
    final db = await _helper.database;

    final rows = await db.rawQuery('''
      SELECT l.recorded_at, l.quantity_deducted,
             b.container_capacity,
             i.ingredient_id, i.name AS ingredient_name, i.unit_of_measure
      FROM loss_events l
      JOIN inventory_batches b ON b.batch_id = l.batch_id
      JOIN ingredients i ON i.ingredient_id = b.ingredient_id
      WHERE l.recorded_at >= ? AND l.recorded_at <= ?
        ${ingredientId == null ? '' : 'AND i.ingredient_id = ?'}
    ''', [
      from.toIso8601String(),
      to.toIso8601String(),
      ?ingredientId,
    ]);

    return rows
        .map((row) => _toRecord(
              row,
              occurredAt: row['recorded_at'] as String,
              quantity: (row['quantity_deducted'] as num).toDouble(),
              category: LossCategory.declared,
            ))
        .toList();
  }

  Future<List<LossRecord>> _getUnexplainedLosses(
    DateTime from,
    DateTime to,
    int? ingredientId,
  ) async {
    final db = await _helper.database;

    // only shortfalls count as loss, a surplus is not waste
    // and unrecorded_receiving is excluded outright, it's a bookkeeping correction
    // reconciliation_logs has no timestamp of its own so the shift's close time is used
    final rows = await db.rawQuery('''
      SELECT COALESCE(s.closed_at, s.opened_at) AS occurred_at,
             r.variance,
             b.container_capacity,
             i.ingredient_id, i.name AS ingredient_name, i.unit_of_measure
      FROM reconciliation_logs r
      JOIN shift_sessions s ON s.shift_id = r.shift_id
      JOIN inventory_batches b ON b.batch_id = r.batch_id
      JOIN ingredients i ON i.ingredient_id = b.ingredient_id
      WHERE r.variance < 0
        AND r.variance_type = 'unexplained'
        AND COALESCE(s.closed_at, s.opened_at) >= ?
        AND COALESCE(s.closed_at, s.opened_at) <= ?
        ${ingredientId == null ? '' : 'AND i.ingredient_id = ?'}
    ''', [
      from.toIso8601String(),
      to.toIso8601String(),
      ?ingredientId,
    ]);

    return rows
        .map((row) => _toRecord(
              row,
              occurredAt: row['occurred_at'] as String,
              // variance is negative for a shortfall, the chart wants a positive amount
              quantity: (row['variance'] as num).toDouble().abs(),
              category: LossCategory.unexplained,
            ))
        .toList();
  }

  LossRecord _toRecord(
    Map<String, Object?> row, {
    required String occurredAt,
    required double quantity,
    required LossCategory category,
  }) {
    final capacity = (row['container_capacity'] as num).toDouble();

    return LossRecord(
      occurredAt: DateTime.parse(occurredAt),
      ingredientId: row['ingredient_id'] as int,
      ingredientName: row['ingredient_name'] as String,
      unitOfMeasure: row['unit_of_measure'] as String,
      category: category,
      quantity: quantity,
      // guard against a zero capacity so this can't divide by zero
      containersEquivalent: capacity > 0 ? quantity / capacity : 0,
    );
  }
}
