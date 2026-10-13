/// where a loss came from, these are the chart's categories
///
/// declared losses are known incidents like a dropped bottle, unexplained is the
/// mystery drift the closing count turns up, keeping them apart is the point of
/// having loss_events as its own table
enum LossCategory {
  declared('Declared loss'),
  unexplained('Unexplained');

  const LossCategory(this.label);

  final String label;
}

/// one loss, from either loss_events or a shortfall in reconciliation_logs
class LossRecord {
  final DateTime occurredAt;
  final int ingredientId;
  final String ingredientName;
  final String unitOfMeasure;
  final LossCategory category;

  /// how much was lost, in the ingredient's own unit, always positive
  final double quantity;

  /// the same loss expressed as containers, used when the chart mixes ingredients
  /// since ml and g can't share a y axis but containers can
  final double containersEquivalent;

  const LossRecord({
    required this.occurredAt,
    required this.ingredientId,
    required this.ingredientName,
    required this.unitOfMeasure,
    required this.category,
    required this.quantity,
    required this.containersEquivalent,
  });
}
