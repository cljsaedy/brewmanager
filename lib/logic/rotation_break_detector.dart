/// spots a probable break in expiry order rotation
///
/// when two batches of the same ingredient come back with variances that roughly
/// cancel out, one surplus and one deficit, nothing was actually lost, stock was
/// taken from the wrong container
///
/// example: batch A expected 1500 counted 2000 (+500), batch B expected 2000
/// counted 1500 (−500), the 500 moved between cartons rather than disappearing
///
/// the flag is informational, the write-back still corrects both batches, and it is
/// worked out here at display time rather than stored because variance_type only
/// allows three values and this is a pattern across two rows, not a property of one
library;

import '../models/audit_batch.dart';

/// one detected pair
class RotationBreak {
  final String ingredientName;
  final String unitOfMeasure;
  final AuditResult surplus;
  final AuditResult deficit;

  const RotationBreak({
    required this.ingredientName,
    required this.unitOfMeasure,
    required this.surplus,
    required this.deficit,
  });

  /// the amount that looks like it moved between the two batches, the smaller of the two
  double get amountMoved {
    final s = surplus.variance.abs();
    final d = deficit.variance.abs();
    return s < d ? s : d;
  }
}

class RotationBreakDetector {
  RotationBreakDetector._();

  /// how close to cancelling the pair must be, as a share of the smaller variance
  static const double cancelTolerance = 0.20;

  /// variances below this share of a container are measurement slop, not rotation
  /// expressed against the container size so it works for ml and g alike
  static const double noiseFloorOfContainer = 0.05;

  /// finds cancelling surplus/deficit pairs among one audit's results
  static List<RotationBreak> detect(List<AuditResult> results) {
    final byIngredient = <int, List<AuditResult>>{};
    for (final r in results) {
      // unrecorded receiving is a bookkeeping correction, not misrotation
      if (r.varianceType == VarianceType.unrecordedReceiving) continue;
      if (!_isAboveNoiseFloor(r)) continue;
      byIngredient.putIfAbsent(r.auditBatch.ingredientId, () => []).add(r);
    }

    final breaks = <RotationBreak>[];

    for (final group in byIngredient.values) {
      // need at least one of each to have anything cancel
      final surpluses = group.where((r) => r.isSurplus).toList()
        ..sort((a, b) => b.variance.abs().compareTo(a.variance.abs()));
      final deficits = group.where((r) => r.isDeficit).toList()
        ..sort((a, b) => b.variance.abs().compareTo(a.variance.abs()));

      // pair the biggest surplus with the biggest deficit, then the next, and so on
      // a batch can only belong to one pair, so both lists are consumed together
      final usedDeficits = <AuditResult>{};

      for (final surplus in surpluses) {
        AuditResult? bestMatch;
        var bestRemainder = double.infinity;

        for (final deficit in deficits) {
          if (usedDeficits.contains(deficit)) continue;
          if (!_roughlyCancels(surplus.variance, deficit.variance)) continue;

          // closest to cancelling wins when several would qualify
          final remainder = (surplus.variance + deficit.variance).abs();
          if (remainder < bestRemainder) {
            bestRemainder = remainder;
            bestMatch = deficit;
          }
        }

        if (bestMatch != null) {
          usedDeficits.add(bestMatch);
          breaks.add(RotationBreak(
            ingredientName: surplus.auditBatch.ingredientName,
            unitOfMeasure: surplus.auditBatch.unitOfMeasure,
            surplus: surplus,
            deficit: bestMatch,
          ));
        }
      }
    }

    return breaks;
  }

  static bool _isAboveNoiseFloor(AuditResult r) {
    final floor = r.auditBatch.containerCapacity * noiseFloorOfContainer;
    return r.variance.abs() > floor;
  }

  /// true when adding the two together leaves little compared to the smaller one
  static bool _roughlyCancels(double surplus, double deficit) {
    final smaller =
        surplus.abs() < deficit.abs() ? surplus.abs() : deficit.abs();
    if (smaller == 0) return false;
    return (surplus + deficit).abs() <= smaller * cancelTolerance;
  }
}
