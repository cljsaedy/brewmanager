/// ranks menu items by how much selling them would prevent waste
///
/// this is the decision support module, and it is deterministic rule based scoring,
/// no machine learning, the point is waste prevention rather than up-selling
///
/// score = (expiryWeight × highest expiry risk among the item's ingredients)
///       + (popularityWeight × how often it sold in the last 7 days)
///
/// pure dart so it can be unit tested, the repository fetches the inputs
library;

import '../models/menu_item.dart';
import '../models/recipe_blueprint.dart';
import 'availability_calculator.dart';
import 'expiry_risk.dart';
import 'fefo_engine.dart';

/// one menu item's inputs, assembled by the repository
class SuggestionCandidate {
  final MenuItem menuItem;
  final List<RecipeBlueprint> recipeLines;

  /// how many of this item sold in the trailing 7 days
  final int timesSold;

  const SuggestionCandidate({
    required this.menuItem,
    required this.recipeLines,
    required this.timesSold,
  });
}

/// one ranked suggestion, with everything suggestion_logs needs
class Suggestion {
  final MenuItem menuItem;
  final double expiryRiskScore;
  final double popularityScore;
  final double combinedScore;

  /// the batch that drove the risk, this is what gets logged
  final int? batchId;

  /// the ingredient in that batch, for the reason text
  final String? riskIngredientName;

  /// days until that batch expires, negative when already past
  final int? daysUntilExpiry;

  /// how many servings the stock can still cover
  final int servingsPossible;

  const Suggestion({
    required this.menuItem,
    required this.expiryRiskScore,
    required this.popularityScore,
    required this.combinedScore,
    required this.batchId,
    required this.riskIngredientName,
    required this.daysUntilExpiry,
    required this.servingsPossible,
  });

  /// true when there is something actually worth pushing, a green item is not urgent
  bool get isUrgent => expiryRiskScore > 0;

  /// plain words for the barista, the spec wants the reason shown with the item
  String get reason {
    if (riskIngredientName == null || daysUntilExpiry == null) {
      return 'Popular item, no stock expiring soon.';
    }

    final name = riskIngredientName!;
    final days = daysUntilExpiry!;

    final when = days < 0
        ? 'has expired'
        : days == 0
            ? 'expires today'
            : days == 1
                ? 'expires tomorrow'
                : 'expires in $days days';

    if (expiryRiskScore == 0) {
      return '$name $when — nothing urgent.';
    }
    return '$name $when — this item is the best way to use it up.';
  }
}

/// the ranked list plus whether the ranking had sales history to work with
class SuggestionRanking {
  final List<Suggestion> suggestions;

  /// true when there were no sales in the window, so ranking fell back to expiry only
  final bool isColdStart;

  const SuggestionRanking({
    required this.suggestions,
    required this.isColdStart,
  });

  /// the one to show, null when nothing can be made
  Suggestion? get top => suggestions.isEmpty ? null : suggestions.first;
}

class SuggestionEngine {
  SuggestionEngine._();

  /// the weighting from the spec, kept as parameters so the evaluation can compare
  /// 60/40 against 50/50, 70/30 and 80/20 on real transaction data
  static const double defaultExpiryWeight = 0.6;
  static const double defaultPopularityWeight = 0.4;

  static SuggestionRanking rank({
    required List<SuggestionCandidate> candidates,
    required Map<int, List<BatchStock>> stockByIngredient,
    required DateTime today,
    double expiryWeight = defaultExpiryWeight,
    double popularityWeight = defaultPopularityWeight,
  }) {
    final totals = AvailabilityCalculator.totalsByIngredient(stockByIngredient);

    // the busiest item in the window is the yardstick, popularity is relative to it
    var maxSold = 0;
    for (final c in candidates) {
      if (c.timesSold > maxSold) maxSold = c.timesSold;
    }

    // no sales at all in the window, e.g. the first week of deployment
    // without this every popularity would be 0 and the ranking would be meaningless ties
    final isColdStart = maxSold == 0;

    final suggestions = <Suggestion>[];

    for (final candidate in candidates) {
      final availability = AvailabilityCalculator.forMenuItemFromTotals(
        candidate.recipeLines,
        totals,
      );

      // never suggest something that can't be made, that's worse than suggesting nothing
      if (!availability.canMakeAtLeastOne) continue;

      final risk = _highestRisk(candidate, stockByIngredient, today);

      final popularity = isColdStart ? 0.0 : candidate.timesSold / maxSold;

      // cold start ranks on expiry risk alone rather than letting a zero popularity
      // term drag every score down equally
      final combined = isColdStart
          ? risk.score
          : (expiryWeight * risk.score) + (popularityWeight * popularity);

      suggestions.add(Suggestion(
        menuItem: candidate.menuItem,
        expiryRiskScore: risk.score,
        popularityScore: popularity,
        combinedScore: combined,
        batchId: risk.batchId,
        riskIngredientName: risk.ingredientName,
        daysUntilExpiry: risk.daysUntilExpiry,
        servingsPossible: availability.servings,
      ));
    }

    // highest score first, ties broken by the sooner expiry so the urgent one wins
    suggestions.sort((a, b) {
      final byScore = b.combinedScore.compareTo(a.combinedScore);
      if (byScore != 0) return byScore;
      final aDays = a.daysUntilExpiry ?? 99999;
      final bDays = b.daysUntilExpiry ?? 99999;
      return aDays.compareTo(bDays);
    });

    return SuggestionRanking(
      suggestions: suggestions,
      isColdStart: isColdStart,
    );
  }

  /// the riskiest batch among everything this item uses
  ///
  /// one item can use several ingredients, the most at risk one decides the score
  /// and names the reason
  static _Risk _highestRisk(
    SuggestionCandidate candidate,
    Map<int, List<BatchStock>> stockByIngredient,
    DateTime today,
  ) {
    var best = const _Risk(score: 0, batchId: null, ingredientName: null, daysUntilExpiry: null);

    for (final line in candidate.recipeLines) {
      final batches = stockByIngredient[line.ingredientId] ?? const [];

      for (final batch in batches) {
        final band = ExpiryRisk.bandFor(batch.expiryDate, today);
        final days = ExpiryRisk.daysUntil(batch.expiryDate, today);

        // a higher band wins, and on an equal band the sooner expiry wins
        final isBetter = band.score > best.score ||
            (band.score == best.score &&
                best.daysUntilExpiry != null &&
                days < best.daysUntilExpiry!);

        if (isBetter || best.batchId == null) {
          best = _Risk(
            score: band.score,
            batchId: batch.batchId,
            ingredientName: line.ingredientName,
            daysUntilExpiry: days,
          );
        }
      }
    }

    return best;
  }
}

/// the riskiest batch found for an item
class _Risk {
  final double score;
  final int? batchId;
  final String? ingredientName;
  final int? daysUntilExpiry;

  const _Risk({
    required this.score,
    required this.batchId,
    required this.ingredientName,
    required this.daysUntilExpiry,
  });
}
