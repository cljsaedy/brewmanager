/// a row from loss_events, a loss someone recorded at the time it happened
///
/// kept apart from the unexplained drift the closing count finds, so the loss
/// chart can tell a dropped carton from a mystery
class DeclaredLoss {
  final int lossEventId;
  final int shiftId;
  final int batchId;
  final int containersLost;
  final double quantityDeducted;
  final String recordedAt; // ISO-8601

  // from the joins, for showing it in a list
  final String ingredientName;
  final String unitOfMeasure;
  final double containerCapacity;
  final String recordedBy;

  const DeclaredLoss({
    required this.lossEventId,
    required this.shiftId,
    required this.batchId,
    required this.containersLost,
    required this.quantityDeducted,
    required this.recordedAt,
    required this.ingredientName,
    required this.unitOfMeasure,
    required this.containerCapacity,
    required this.recordedBy,
  });

  factory DeclaredLoss.fromMap(Map<String, Object?> map) {
    return DeclaredLoss(
      lossEventId: map['loss_event_id'] as int,
      shiftId: map['shift_id'] as int,
      batchId: map['batch_id'] as int,
      containersLost: map['containers_lost'] as int,
      quantityDeducted: (map['quantity_deducted'] as num).toDouble(),
      recordedAt: map['recorded_at'] as String,
      ingredientName: map['ingredient_name'] as String,
      unitOfMeasure: map['unit_of_measure'] as String,
      containerCapacity: (map['container_capacity'] as num).toDouble(),
      recordedBy: map['recorded_by'] as String,
    );
  }

  /// how much was in the lost containers, in containers
  ///
  /// a full carton reads as 1, a part used one as less, which is what makes the
  /// recorded figure checkable against what actually happened
  double get containersWorth =>
      containerCapacity > 0 ? quantityDeducted / containerCapacity : 0;
}
