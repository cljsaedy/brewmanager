/// a row from inventory_batches, one expiry date + one container size = one batch
class InventoryBatch {
  final int batchId;
  final int ingredientId;
  final String expiryDate; // YYYY-MM-DD so it sorts right as text
  final double containerCapacity;
  final int containersReceived;
  final double quantityRemaining;
  final String receivedAt; // full ISO-8601 timestamp

  const InventoryBatch({
    required this.batchId,
    required this.ingredientId,
    required this.expiryDate,
    required this.containerCapacity,
    required this.containersReceived,
    required this.quantityRemaining,
    required this.receivedAt,
  });

  factory InventoryBatch.fromMap(Map<String, Object?> map) {
    return InventoryBatch(
      batchId: map['batch_id'] as int,
      ingredientId: map['ingredient_id'] as int,
      expiryDate: map['expiry_date'] as String,
      containerCapacity: (map['container_capacity'] as num).toDouble(),
      containersReceived: map['containers_received'] as int,
      quantityRemaining: (map['quantity_remaining'] as num).toDouble(),
      receivedAt: map['received_at'] as String,
    );
  }
}

/// a batch plus its ingredient's name and unit, for screens that list batches
class BatchWithIngredient {
  final InventoryBatch batch;
  final String ingredientName;
  final String unitOfMeasure;

  const BatchWithIngredient({
    required this.batch,
    required this.ingredientName,
    required this.unitOfMeasure,
  });

  factory BatchWithIngredient.fromMap(Map<String, Object?> map) {
    return BatchWithIngredient(
      batch: InventoryBatch.fromMap(map),
      ingredientName: map['ingredient_name'] as String,
      unitOfMeasure: map['unit_of_measure'] as String,
    );
  }

  /// whole containers the remaining quantity could still fill, what a loss can be capped at
  int get wholeContainersLeft =>
      (batch.quantityRemaining / batch.containerCapacity).ceil();
}

/// a batch the user has filled in but not saved yet, what the receiving screen collects before Save
class NewBatch {
  final int ingredientId;
  final String ingredientName; // for the pending list only, not stored
  final String unitOfMeasure;
  final DateTime expiryDate;
  final double containerCapacity;
  final int containersReceived;

  const NewBatch({
    required this.ingredientId,
    required this.ingredientName,
    required this.unitOfMeasure,
    required this.expiryDate,
    required this.containerCapacity,
    required this.containersReceived,
  });

  /// starting stock = size of one container × how many came in
  double get totalQuantity => containerCapacity * containersReceived;

  /// the three things that define a batch (rule 1), if all match it's the same batch
  bool isSameBatchAs(NewBatch other) =>
      ingredientId == other.ingredientId &&
      formatDate(expiryDate) == formatDate(other.expiryDate) &&
      containerCapacity == other.containerCapacity;

  /// copy with the count bumped, used when the same batch is added twice
  NewBatch withMoreContainers(int extra) => NewBatch(
        ingredientId: ingredientId,
        ingredientName: ingredientName,
        unitOfMeasure: unitOfMeasure,
        expiryDate: expiryDate,
        containerCapacity: containerCapacity,
        containersReceived: containersReceived + extra,
      );
}

/// YYYY-MM-DD, done by hand so we don't need a date package
String formatDate(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
