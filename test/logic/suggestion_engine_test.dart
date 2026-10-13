import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/fefo_engine.dart';
import 'package:brewmanager/logic/suggestion_engine.dart';
import 'package:brewmanager/models/menu_item.dart';
import 'package:brewmanager/models/recipe_blueprint.dart';

void main() {
  // fixed today so the bands never depend on when the tests run
  final today = DateTime(2026, 10, 12);

  String inDays(int n) {
    final d = today.add(Duration(days: n));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  MenuItem item(int id, String name) => MenuItem(
        menuItemId: id,
        name: name,
        sellingPrice: 100,
        isArchived: false,
      );

  RecipeBlueprint line(int ingredientId, String name, double required) =>
      RecipeBlueprint(
        blueprintId: ingredientId,
        menuItemId: 0,
        ingredientId: ingredientId,
        quantityRequired: required,
        ingredientName: name,
        unitOfMeasure: 'ml',
      );

  BatchStock batch(int id, String expiry, double qty) =>
      BatchStock(batchId: id, expiryDate: expiry, quantityRemaining: qty);

  group('SuggestionEngine.rank — expiry risk', () {
    test('an item using red stock outranks one using green stock', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          // latte uses milk expiring in 10 days (green)
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 5,
          ),
          // mocha uses syrup expiring tomorrow (red)
          SuggestionCandidate(
            menuItem: item(2, 'Mocha'),
            recipeLines: [line(20, 'Chocolate Syrup', 30)],
            timesSold: 5,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(10), 1000)],
          20: [batch(2, inDays(1), 750)],
        },
        today: today,
      );

      expect(ranking.top!.menuItem.name, 'Mocha');
      expect(ranking.top!.expiryRiskScore, 1.0);
      expect(ranking.suggestions[1].expiryRiskScore, 0.0);
    });

    test('the riskiest ingredient of several decides the score', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          // beans are fine, milk is nearly out of date, milk should win
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [
              line(10, 'Espresso Beans', 18),
              line(20, 'Fresh Milk', 200),
            ],
            timesSold: 1,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(30), 1000)],
          20: [batch(2, inDays(1), 1000)],
        },
        today: today,
      );

      expect(ranking.top!.expiryRiskScore, 1.0);
      expect(ranking.top!.riskIngredientName, 'Fresh Milk');
      expect(ranking.top!.batchId, 2);
      expect(ranking.top!.daysUntilExpiry, 1);
    });

    test('yellow scores half', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 1,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(5), 1000)],
        },
        today: today,
      );

      expect(ranking.top!.expiryRiskScore, 0.5);
    });
  });

  group('SuggestionEngine.rank — popularity and weighting', () {
    test('popularity is relative to the busiest item', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 10,
          ),
          SuggestionCandidate(
            menuItem: item(2, 'Cappuccino'),
            recipeLines: [line(10, 'Fresh Milk', 150)],
            timesSold: 5,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(30), 5000)],
        },
        today: today,
      );

      final latte =
          ranking.suggestions.firstWhere((s) => s.menuItem.menuItemId == 1);
      final capp =
          ranking.suggestions.firstWhere((s) => s.menuItem.menuItemId == 2);

      expect(latte.popularityScore, 1.0);
      expect(capp.popularityScore, 0.5);
    });

    test('combined score uses the 60/40 split from the spec', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 10,
          ),
          SuggestionCandidate(
            menuItem: item(2, 'Cappuccino'),
            recipeLines: [line(20, 'Chocolate Syrup', 30)],
            timesSold: 5,
          ),
        ],
        stockByIngredient: {
          // milk yellow (0.5), latte is the most popular (1.0)
          10: [batch(1, inDays(5), 5000)],
          // syrup green (0.0), cappuccino half as popular (0.5)
          20: [batch(2, inDays(30), 750)],
        },
        today: today,
      );

      final latte =
          ranking.suggestions.firstWhere((s) => s.menuItem.menuItemId == 1);
      final capp =
          ranking.suggestions.firstWhere((s) => s.menuItem.menuItemId == 2);

      // 0.6 × 0.5 + 0.4 × 1.0 = 0.7
      expect(latte.combinedScore, closeTo(0.7, 1e-9));
      // 0.6 × 0.0 + 0.4 × 0.5 = 0.2
      expect(capp.combinedScore, closeTo(0.2, 1e-9));
    });

    test('different weights change the ranking, which the evaluation needs', () {
      final candidates = [
        // risky but unpopular
        SuggestionCandidate(
          menuItem: item(1, 'Mocha'),
          recipeLines: [line(20, 'Chocolate Syrup', 30)],
          timesSold: 1,
        ),
        // safe but very popular
        SuggestionCandidate(
          menuItem: item(2, 'Latte'),
          recipeLines: [line(10, 'Fresh Milk', 200)],
          timesSold: 10,
        ),
      ];
      final stock = {
        10: [batch(1, inDays(30), 5000)],
        20: [batch(2, inDays(1), 750)],
      };

      // 60/40: mocha 0.6×1.0 + 0.4×0.1 = 0.64, latte 0.6×0 + 0.4×1 = 0.40
      final sixtyForty = SuggestionEngine.rank(
        candidates: candidates,
        stockByIngredient: stock,
        today: today,
      );
      expect(sixtyForty.top!.menuItem.name, 'Mocha');

      // 20/80 tips it the other way: mocha 0.2+0.08 = 0.28, latte 0+0.8 = 0.80
      final twentyEighty = SuggestionEngine.rank(
        candidates: candidates,
        stockByIngredient: stock,
        today: today,
        expiryWeight: 0.2,
        popularityWeight: 0.8,
      );
      expect(twentyEighty.top!.menuItem.name, 'Latte');
    });
  });

  group('SuggestionEngine.rank — cold start', () {
    test('no sales history falls back to expiry risk only', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 0,
          ),
          SuggestionCandidate(
            menuItem: item(2, 'Mocha'),
            recipeLines: [line(20, 'Chocolate Syrup', 30)],
            timesSold: 0,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(30), 1000)],
          20: [batch(2, inDays(1), 750)],
        },
        today: today,
      );

      expect(ranking.isColdStart, isTrue);
      // ranked on expiry alone, so the red one wins outright
      expect(ranking.top!.menuItem.name, 'Mocha');
      expect(ranking.top!.combinedScore, 1.0);
      expect(ranking.top!.popularityScore, 0);
    });

    test('any sales at all leaves cold start behind', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 1,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(30), 1000)],
        },
        today: today,
      );

      expect(ranking.isColdStart, isFalse);
    });
  });

  group('SuggestionEngine.rank — availability', () {
    test('an item that cannot be made is never suggested', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          // mocha needs 30ml of syrup but only 10ml is left, even though it's red
          SuggestionCandidate(
            menuItem: item(1, 'Mocha'),
            recipeLines: [line(20, 'Chocolate Syrup', 30)],
            timesSold: 5,
          ),
          SuggestionCandidate(
            menuItem: item(2, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 5,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(30), 1000)],
          20: [batch(2, inDays(1), 10)],
        },
        today: today,
      );

      expect(ranking.suggestions.length, 1);
      expect(ranking.top!.menuItem.name, 'Latte');
    });

    test('an item with no recipe is never suggested', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Mystery Drink'),
            recipeLines: const [],
            timesSold: 99,
          ),
        ],
        stockByIngredient: {},
        today: today,
      );

      expect(ranking.suggestions, isEmpty);
      expect(ranking.top, isNull);
    });

    test('servings possible is reported with the suggestion', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 1,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(1), 1000)],
        },
        today: today,
      );

      expect(ranking.top!.servingsPossible, 5);
    });
  });

  group('Suggestion.reason', () {
    test('names the ingredient and when it expires', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 1,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(2), 1000)],
        },
        today: today,
      );

      expect(
        ranking.top!.reason,
        'Fresh Milk expires in 2 days — this item is the best way to use it up.',
      );
    });

    test('wording for today and tomorrow', () {
      Suggestion suggestionFor(int days) {
        return SuggestionEngine.rank(
          candidates: [
            SuggestionCandidate(
              menuItem: item(1, 'Latte'),
              recipeLines: [line(10, 'Fresh Milk', 200)],
              timesSold: 1,
            ),
          ],
          stockByIngredient: {
            10: [batch(1, inDays(days), 1000)],
          },
          today: today,
        ).top!;
      }

      expect(suggestionFor(0).reason, contains('expires today'));
      expect(suggestionFor(1).reason, contains('expires tomorrow'));
      expect(suggestionFor(-1).reason, contains('has expired'));
    });

    test('nothing urgent is said plainly', () {
      final ranking = SuggestionEngine.rank(
        candidates: [
          SuggestionCandidate(
            menuItem: item(1, 'Latte'),
            recipeLines: [line(10, 'Fresh Milk', 200)],
            timesSold: 1,
          ),
        ],
        stockByIngredient: {
          10: [batch(1, inDays(30), 1000)],
        },
        today: today,
      );

      expect(ranking.top!.isUrgent, isFalse);
      expect(ranking.top!.reason, contains('nothing urgent'));
    });
  });
}
