/// the arithmetic behind the closing stock count
///
/// pure dart so it can be unit tested, this is the maths the whole correction loop
/// rests on so a silent bug here would corrupt every batch quantity
library;

/// how the opened-container control steps, a quarter of a container at a time
///
/// it deliberately does NOT cap at 1, it goes ¼, ½, ¾, 1, 1¼, 1½ and on,
/// so the barista reports one combined number no matter how many containers are
/// open and the number of inputs per batch stays at two
const double kOpenedStep = 0.25;

/// what the barista entered for one batch
class AuditEntry {
  /// unopened containers counted
  final int sealedCount;

  /// how much is left across ALL opened containers, in containers (so 1.25 = one and a quarter)
  final double openedTotal;

  const AuditEntry({required this.sealedCount, required this.openedTotal});

  /// total containers worth counted, sealed plus whatever is in the opened ones
  double get totalContainers => sealedCount + openedTotal;
}

class AuditMath {
  AuditMath._();

  /// audited_quantity = (sealed × capacity) + (opened_total × capacity)
  static double auditedQuantity(AuditEntry entry, double containerCapacity) {
    return (entry.sealedCount * containerCapacity) +
        (entry.openedTotal * containerCapacity);
  }

  /// what the count says minus what the system thought, positive means more on the shelf than expected
  static double variance(double auditedQuantity, double theoreticalQuantity) {
    final v = auditedQuantity - theoreticalQuantity;
    // clamp float noise like -4.5e-14 so a perfect count reads as exactly zero
    return v.abs() < 1e-9 ? 0 : v;
  }

  /// starting position for the two controls, rebuilt from last shift's counted quantity
  ///
  /// reconciliation_logs keeps audited_quantity but not the sealed/opened split, so the
  /// split is reconstructed as whole containers plus the remainder, the total is identical
  /// which is all that matters since the barista adjusts from here
  ///
  /// this is LAST SHIFT'S count, never this shift's theoretical, so the audit stays blind
  static AuditEntry startingEntry(
    double? lastAuditedQuantity,
    double containerCapacity,
  ) {
    // never audited before, start from nothing and let the barista count it
    if (lastAuditedQuantity == null || containerCapacity <= 0) {
      return const AuditEntry(sealedCount: 0, openedTotal: 0);
    }

    final totalContainers = lastAuditedQuantity / containerCapacity;
    final sealed = totalContainers.floor();
    final opened = roundToStep(totalContainers - sealed);

    return AuditEntry(
      sealedCount: sealed < 0 ? 0 : sealed,
      openedTotal: opened,
    );
  }

  /// snaps a value onto the nearest quarter, the control can only sit on real steps
  static double roundToStep(double value) {
    if (value <= 0) return 0;
    return (value / kOpenedStep).round() * kOpenedStep;
  }

  /// containers that could possibly be on the shelf for this batch
  ///
  /// received minus any declared losses, containers_received is left as the historical
  /// "how many arrived" so the ceiling is worked out here instead
  static int containersPossible({
    required int containersReceived,
    required int containersLost,
  }) {
    final possible = containersReceived - containersLost;
    return possible < 0 ? 0 : possible;
  }

  /// true when the sealed count alone is more than could exist
  ///
  /// this is the one thing the audit may reveal (rule 5), because it says the count is
  /// impossible without saying what the right number is
  static bool isImpossibleCount({
    required int sealedCount,
    required int containersPossible,
  }) {
    return sealedCount > containersPossible;
  }
}
