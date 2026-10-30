/// works out how many servings of a menu item the current stock can cover
///
/// pure dart, no db, so it can be unit tested, the repository fetches the stock and hands it in
library;

import '../models/recipe_blueprint.dart';
import 'fefo_engine.dart';

/// how many servings are possible and why, used by the pos grid for grayout
class Availability {
  /// how many whole servings the stock can cover
  final int servings;

  /// true when the menu item has no recipe lines at all
  final bool hasNoRecipe;

  /// false for food sold as a whole unit, which has no stock to run out of
  final bool isTracked;

  /// ingredient that ran out first, null when nothing is short
  final String? limitingIngredient;

  /// true when the limiting ingredient has stock on the shelf but all of it has
  /// expired, so the item is blocked for a different reason than running out
  ///
  /// without this the till would say "out of fresh milk" while the stock screen
  /// shows plenty of milk, which reads as a bug rather than as a safety rule
  final bool blockedByExpiry;

  const Availability({
    required this.servings,
    this.hasNoRecipe = false,
    this.isTracked = true,
    this.limitingIngredient,
    this.blockedByExpiry = false,
  });

  /// an untracked item is always sellable, there is no stock behind it to check
  bool get canMakeAtLeastOne => !isTracked || servings > 0;

  /// whether a "N left" count means anything for this item
  bool get hasServingLimit => isTracked;
}

class AvailabilityCalculator {
  AvailabilityCalculator._();

  /// adds up each ingredient's batches into one number per ingredient
  static Map<int, double> totalsByIngredient(
    Map<int, List<BatchStock>> stockByIngredient,
  ) {
    return {
      for (final entry in stockByIngredient.entries)
        entry.key: entry.value.fold<double>(
          0,
          (sum, b) => sum + b.quantityRemaining,
        ),
    };
  }

  /// how much of each ingredient the order already claims
  ///
  /// needed because two drinks can share an ingredient, 2 lattes and 2 cappuccinos
  /// both using milk must not each think the full milk stock is theirs
  static Map<int, double> consumedByOrder(
    Map<int, int> quantityByMenuItemId,
    Map<int, List<RecipeBlueprint>> recipesByMenuItemId,
  ) {
    final consumed = <int, double>{};
    for (final entry in quantityByMenuItemId.entries) {
      final lines = recipesByMenuItemId[entry.key] ?? const [];
      for (final line in lines) {
        consumed[line.ingredientId] = (consumed[line.ingredientId] ?? 0) +
            line.quantityRequired * entry.value;
      }
    }
    return consumed;
  }

  /// subtracts what the order claims from the stock totals, never goes below zero
  static Map<int, double> totalsAfterOrder(
    Map<int, double> totals,
    Map<int, double> consumed,
  ) {
    final left = <int, double>{...totals};
    for (final entry in consumed.entries) {
      final remaining = (left[entry.key] ?? 0) - entry.value;
      left[entry.key] = remaining < 0 ? 0 : remaining;
    }
    return left;
  }

  /// [stockByIngredient] is every batch of every ingredient, keyed by ingredient_id
  static Availability forMenuItem(
    List<RecipeBlueprint> recipeLines,
    Map<int, List<BatchStock>> stockByIngredient, {
    bool isIngredientTracked = true,
  }) {
    return forMenuItemFromTotals(
      recipeLines,
      totalsByIngredient(stockByIngredient),
      isIngredientTracked: isIngredientTracked,
    );
  }

  /// same thing but from already totalled stock, what the pos uses after subtracting the order
  /// [expiredByIngredient] is stock that exists but has gone past its expiry
  /// date, used only to explain why an item is blocked, never to cover an order
  static Availability forMenuItemFromTotals(
    List<RecipeBlueprint> recipeLines,
    Map<int, double> availableByIngredient, {
    bool isIngredientTracked = true,
    Map<int, double> expiredByIngredient = const {},
  }) {
    // food sold as a whole unit has no ingredients behind it, so there is
    // nothing to run out of and it is always sellable
    if (!isIngredientTracked) {
      return const Availability(servings: 0, isTracked: false);
    }

    // a tracked item with no recipe would deduct nothing on a sale, which for a
    // drink means the recipe was never set, so it stays unsellable until it is
    if (recipeLines.isEmpty) {
      return const Availability(servings: 0, hasNoRecipe: true);
    }

    var lowestServings = -1;
    String? limiting;
    var limitingId = -1;

    for (final line in recipeLines) {
      final available = availableByIngredient[line.ingredientId] ?? 0;

      // whole servings only, you can't sell half a drink
      final servings = (available / line.quantityRequired).floor();

      // the ingredient with the fewest servings is the limit
      if (lowestServings == -1 || servings < lowestServings) {
        lowestServings = servings;
        limiting = line.ingredientName;
        limitingId = line.ingredientId;
      }
    }

    // nothing usable left, but there is expired stock of it on the shelf, so
    // the reason is the expiry date rather than an empty fridge
    final blockedByExpiry =
        lowestServings == 0 && (expiredByIngredient[limitingId] ?? 0) > 0;

    return Availability(
      servings: lowestServings,
      // only name the limiting ingredient when it's actually blocking
      limitingIngredient: lowestServings == 0 ? limiting : null,
      blockedByExpiry: blockedByExpiry,
    );
  }
}
