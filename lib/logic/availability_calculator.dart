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

  /// ingredient that ran out first, null when nothing is short
  final String? limitingIngredient;

  const Availability({
    required this.servings,
    this.hasNoRecipe = false,
    this.limitingIngredient,
  });

  bool get canMakeAtLeastOne => servings > 0;
}

class AvailabilityCalculator {
  AvailabilityCalculator._();

  /// [stockByIngredient] is every batch of every ingredient, keyed by ingredient_id
  static Availability forMenuItem(
    List<RecipeBlueprint> recipeLines,
    Map<int, List<BatchStock>> stockByIngredient,
  ) {
    // no recipe means nothing would be deducted on a sale, so treat it as unsellable instead of unlimited
    if (recipeLines.isEmpty) {
      return const Availability(servings: 0, hasNoRecipe: true);
    }

    var lowestServings = -1;
    String? limiting;

    for (final line in recipeLines) {
      final batches = stockByIngredient[line.ingredientId] ?? const [];
      final available = batches.fold<double>(
        0,
        (sum, b) => sum + b.quantityRemaining,
      );

      // whole servings only, you can't sell half a drink
      final servings = (available / line.quantityRequired).floor();

      // the ingredient with the fewest servings is the limit
      if (lowestServings == -1 || servings < lowestServings) {
        lowestServings = servings;
        limiting = line.ingredientName;
      }
    }

    return Availability(
      servings: lowestServings,
      // only name the limiting ingredient when it's actually blocking
      limitingIngredient: lowestServings == 0 ? limiting : null,
    );
  }
}
