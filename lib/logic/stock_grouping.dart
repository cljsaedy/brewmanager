/// gathers batches under their ingredient for the grouped view of the stock screen
///
/// pure dart so the ordering rules can be unit tested, the repository fetches rows
library;

import '../models/inventory_batch.dart';
import 'expiry_risk.dart';

/// every batch of one ingredient, with the total across them
class IngredientStockGroup {
  final int ingredientId;
  final String ingredientName;
  final String unitOfMeasure;

  /// batches in expiry order, which is also the order fefo will use them
  final List<BatchWithIngredient> batches;

  /// everything left of this ingredient, the number the manager is looking for
  final double totalQuantity;

  /// the band of the most urgent batch in the group, for the header's colour
  final ExpiryBand worstBand;

  const IngredientStockGroup({
    required this.ingredientId,
    required this.ingredientName,
    required this.unitOfMeasure,
    required this.batches,
    required this.totalQuantity,
    required this.worstBand,
  });

  int get batchCount => batches.length;
}

class StockGrouping {
  StockGrouping._();

  /// groups by ingredient, alphabetically
  ///
  /// alphabetical rather than most urgent first, because the grouped view is for
  /// looking something up, so milk should be in the same place every time
  /// the flat expiry-ordered view is what answers "what is urgent"
  static List<IngredientStockGroup> byIngredient(
    List<BatchWithIngredient> batches,
    DateTime today,
  ) {
    final grouped = <int, List<BatchWithIngredient>>{};
    for (final batch in batches) {
      grouped.putIfAbsent(batch.batch.ingredientId, () => []).add(batch);
    }

    final groups = grouped.entries.map((entry) {
      // soonest expiry first inside the group, same order fefo deducts in
      final sorted = [...entry.value]
        ..sort((a, b) => a.batch.expiryDate.compareTo(b.batch.expiryDate));

      final total = sorted.fold<double>(
        0,
        (sum, b) => sum + b.batch.quantityRemaining,
      );

      // the worst band present decides the header colour
      var worst = ExpiryBand.green;
      for (final b in sorted) {
        final band = ExpiryRisk.bandFor(b.batch.expiryDate, today);
        if (band.score > worst.score) worst = band;
      }

      return IngredientStockGroup(
        ingredientId: entry.key,
        ingredientName: sorted.first.ingredientName,
        unitOfMeasure: sorted.first.unitOfMeasure,
        batches: sorted,
        totalQuantity: total,
        worstBand: worst,
      );
    }).toList();

    groups.sort((a, b) => a.ingredientName
        .toLowerCase()
        .compareTo(b.ingredientName.toLowerCase()));
    return groups;
  }
}
