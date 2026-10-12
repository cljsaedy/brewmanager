import '../logic/audit_math.dart';
import 'inventory_batch.dart';

/// one batch as the audit screen sees it
///
/// theoreticalQuantity is loaded when the screen opens but NEVER shown until the
/// count is submitted (rule 5), if staff can see the expected number they type it in
class AuditBatch {
  final BatchWithIngredient batch;

  /// what the system thinks is left, computed early and kept hidden
  final double theoreticalQuantity;

  /// containers that could possibly be on the shelf, received minus declared losses
  final int containersPossible;

  /// what the controls start on, rebuilt from last shift's count (not the theoretical)
  final AuditEntry startingEntry;

  const AuditBatch({
    required this.batch,
    required this.theoreticalQuantity,
    required this.containersPossible,
    required this.startingEntry,
  });

  int get batchId => batch.batch.batchId;
  int get ingredientId => batch.batch.ingredientId;
  double get containerCapacity => batch.batch.containerCapacity;
  String get ingredientName => batch.ingredientName;
  String get unitOfMeasure => batch.unitOfMeasure;
  String get expiryDate => batch.batch.expiryDate;
}

/// one finished count, ready to be written back
class AuditResult {
  final AuditBatch auditBatch;
  final AuditEntry entry;
  final double auditedQuantity;
  final double variance;
  final String varianceType;

  const AuditResult({
    required this.auditBatch,
    required this.entry,
    required this.auditedQuantity,
    required this.variance,
    required this.varianceType,
  });

  bool get isSurplus => variance > 0;
  bool get isDeficit => variance < 0;
  bool get isExact => variance == 0;
}

/// the three allowed values of reconciliation_logs.variance_type
class VarianceType {
  VarianceType._();

  /// a gap with no recorded cause, spills and over pours
  static const String unexplained = 'unexplained';

  /// a loss that was declared at the time, already deducted before the audit
  static const String declaredLoss = 'declared_loss';

  /// more sealed containers than were ever recorded, a bookkeeping correction not waste
  static const String unrecordedReceiving = 'unrecorded_receiving';
}
