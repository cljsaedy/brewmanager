/// FEFO = first expired, first out
///
/// pure dart, no db, given the batches an ingredient has and how much a sale needs
/// it returns a plan of which batch gives how much, the checkout applies the plan inside its transaction
/// kept separate so it can be unit tested without sqlite
library;

import 'expiry_risk.dart';

/// the bits of a batch the engine needs, small on purpose so tests are easy to write
class BatchStock {
  final int batchId;
  final String expiryDate; // YYYY-MM-DD, sorts right as text
  final double quantityRemaining;

  const BatchStock({
    required this.batchId,
    required this.expiryDate,
    required this.quantityRemaining,
  });
}

/// one line of the plan, becomes one batch_deductions row (rule 3)
class Deduction {
  final int batchId;
  final double quantity;

  const Deduction({required this.batchId, required this.quantity});

  @override
  String toString() => 'Deduction(batch $batchId, $quantity)';
}

/// result of planning, deductions in the order they should happen plus anything that couldn't be covered
class FefoPlan {
  final List<Deduction> deductions;
  final double shortfall;

  const FefoPlan({required this.deductions, required this.shortfall});

  bool get isFullyCovered => shortfall == 0;
}

class FefoEngine {
  FefoEngine._();

  /// works out which batches to take [needed] from
  /// [today] decides which batches have expired
  ///
  /// required rather than defaulted, because the whole point of this engine is
  /// to deduct from the batch nearest its expiry date, which means an expired
  /// one sorts to the very front and would be deducted first of all unless it
  /// is taken out, and nobody should be able to call this without deciding that
  static FefoPlan plan(
    List<BatchStock> batches,
    double needed, {
    required DateTime today,
  }) {
    // skip empty batches and anything past its expiry date
    //
    // an expired batch is still on the shelf and still gets counted at the
    // closing audit, but it cannot be sold, so it is not stock this engine may
    // draw from
    //
    // then sort earliest expiry first, and on the same expiry date the smaller
    // remaining first so partial containers get finished off (rule 2)
    final sorted = batches
        .where(
          (b) =>
              b.quantityRemaining > 0 &&
              !ExpiryRisk.isExpired(b.expiryDate, today),
        )
        .toList()
      ..sort((a, b) {
        final byExpiry = a.expiryDate.compareTo(b.expiryDate);
        if (byExpiry != 0) return byExpiry;
        return a.quantityRemaining.compareTo(b.quantityRemaining);
      });

    final deductions = <Deduction>[];
    var remaining = needed;

    // multi-batch splitting, keep taking from the next batch until covered
    for (final batch in sorted) {
      if (remaining <= 0) break;

      // take what this batch can give, up to what's still needed
      final take = remaining < batch.quantityRemaining
          ? remaining
          : batch.quantityRemaining;

      deductions.add(Deduction(batchId: batch.batchId, quantity: take));
      remaining -= take;
    }

    // clamp tiny float noise like 1e-13 to zero
    if (remaining < 1e-9) remaining = 0;

    return FefoPlan(deductions: deductions, shortfall: remaining);
  }
}
