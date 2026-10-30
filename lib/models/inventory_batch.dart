/// a row from inventory_batches, one expiry date + one container size = one batch
class InventoryBatch {
  final int batchId;
  final int ingredientId;
  final String expiryDate; // YYYY-MM-DD so it sorts right as text
  final double containerCapacity;
  final int containersReceived;
  final double quantityRemaining;
  final String receivedAt; // full ISO-8601 timestamp

  /// who last corrected figures that were entered wrongly, null if never
  ///
  /// same pattern as transactions.voided_by, the actor is recorded on the row
  /// that was affected rather than in a log of its own
  final int? correctedBy;
  final String? correctedAt;

  /// what quantity_remaining was before the most recent correction
  ///
  /// an expiry or capacity mistake is obvious from the corrected figure, but a
  /// quantity change could hide waste, so this is the before value worth keeping
  ///
  /// only the latest correction is kept, correcting twice loses the earlier one
  final double? previousQuantity;

  const InventoryBatch({
    required this.batchId,
    required this.ingredientId,
    required this.expiryDate,
    required this.containerCapacity,
    required this.containersReceived,
    required this.quantityRemaining,
    required this.receivedAt,
    this.correctedBy,
    this.correctedAt,
    this.previousQuantity,
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
      correctedBy: map['corrected_by'] as int?,
      correctedAt: map['corrected_at'] as String?,
      previousQuantity: (map['previous_quantity'] as num?)?.toDouble(),
    );
  }

  bool get wasCorrected => correctedAt != null;

  /// whether the correction changed the quantity, as opposed to only the
  /// expiry date or the container size
  bool get correctionChangedQuantity =>
      previousQuantity != null && previousQuantity != quantityRemaining;
}

/// a batch plus its ingredient's name and unit, for screens that list batches
class BatchWithIngredient {
  final InventoryBatch batch;
  final String ingredientName;
  final String unitOfMeasure;

  /// who corrected it, from a join, null when it was never corrected
  final String? correctedByName;

  const BatchWithIngredient({
    required this.batch,
    required this.ingredientName,
    required this.unitOfMeasure,
    this.correctedByName,
  });

  factory BatchWithIngredient.fromMap(Map<String, Object?> map) {
    return BatchWithIngredient(
      batch: InventoryBatch.fromMap(map),
      ingredientName: map['ingredient_name'] as String,
      unitOfMeasure: map['unit_of_measure'] as String,
      correctedByName: map['corrected_by_name'] as String?,
    );
  }

  /// whole containers the remaining quantity could still fill, what a loss can be capped at
  int get wholeContainersLeft =>
      (batch.quantityRemaining / batch.containerCapacity).ceil();

  /// how many unopened containers the records imply are on the shelf
  ///
  /// the database keeps a batch's total, not a breakdown per container, so this
  /// is inferred: as many full containers as the total covers, and whatever is
  /// left over is the one that has been opened
  ///
  /// that holds as long as containers are opened one at a time, which is how a
  /// cafe works and what fefo assumes anyway, and it is the same inference the
  /// closing count already makes for its starting figures
  int get impliedSealedCount {
    if (batch.containerCapacity <= 0) return 0;
    final sealed = (_roundedRemaining / batch.containerCapacity).floor();
    // never claim more sealed containers than were ever received
    return sealed > batch.containersReceived
        ? batch.containersReceived
        : sealed;
  }

  /// what the records imply is left in the opened container, 0 when there isn't one
  double get impliedOpenedRemainder {
    final remainder =
        _roundedRemaining - (impliedSealedCount * batch.containerCapacity);
    // a sliver of a millilitre is not an opened container
    return remainder < 0.001 ? 0 : remainder;
  }

  bool get hasOpenedContainer => impliedOpenedRemainder > 0;

  /// the total rounded to the nearest hundredth before it gets divided up
  ///
  /// repeated deductions leave values like 1999.9999999998, and flooring that
  /// against the container size lands one container short, so a nearly full
  /// sealed carton would be described as an opened one with 999.99 left in it
  double get _roundedRemaining =>
      (batch.quantityRemaining * 100).round() / 100;
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
