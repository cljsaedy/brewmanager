import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/availability_calculator.dart';
import 'package:brewmanager/logic/fefo_engine.dart';
import 'package:brewmanager/models/recipe_blueprint.dart';

void main() {
  // helpers so each case reads like a table
  RecipeBlueprint line(int ingredientId, String name, double required) =>
      RecipeBlueprint(
        blueprintId: ingredientId,
        menuItemId: 1,
        ingredientId: ingredientId,
        quantityRequired: required,
        ingredientName: name,
        unitOfMeasure: 'ml',
      );

  BatchStock stock(int id, double qty) =>
      BatchStock(batchId: id, expiryDate: '2026-12-01', quantityRemaining: qty);

  group('AvailabilityCalculator.forMenuItem', () {
    test('single ingredient, divides and floors', () {
      final result = AvailabilityCalculator.forMenuItem(
        [line(1, 'Milk', 200)],
        {
          1: [stock(1, 500)],
        },
      );

      // 500 / 200 = 2.5 → 2 whole servings
      expect(result.servings, 2);
      expect(result.canMakeAtLeastOne, isTrue);
    });

    test('the scarcest ingredient sets the limit', () {
      final result = AvailabilityCalculator.forMenuItem(
        [line(1, 'Beans', 18), line(2, 'Milk', 200)],
        {
          1: [stock(1, 500)], // 27 servings
          2: [stock(2, 300)], // 1 serving
        },
      );

      expect(result.servings, 1);
    });

    test('stock is summed across batches', () {
      final result = AvailabilityCalculator.forMenuItem(
        [line(1, 'Milk', 200)],
        {
          1: [stock(1, 150), stock(2, 150), stock(3, 150)],
        },
      );

      // 450 total / 200 = 2
      expect(result.servings, 2);
    });

    test(
      'missing ingredient stock means zero servings and names the blocker',
      () {
        final result = AvailabilityCalculator.forMenuItem(
          [line(1, 'Beans', 18), line(2, 'Milk', 200)],
          {
            1: [stock(1, 500)],
            // no milk at all
          },
        );

        expect(result.servings, 0);
        expect(result.canMakeAtLeastOne, isFalse);
        expect(result.limitingIngredient, 'Milk');
      },
    );

    test('a menu item with no recipe is unsellable, not unlimited', () {
      final result = AvailabilityCalculator.forMenuItem([], {});

      expect(result.servings, 0);
      expect(result.hasNoRecipe, isTrue);
    });

    test('no limiting ingredient is named when stock is fine', () {
      final result = AvailabilityCalculator.forMenuItem(
        [line(1, 'Milk', 200)],
        {
          1: [stock(1, 1000)],
        },
      );

      expect(result.servings, 5);
      expect(result.limitingIngredient, isNull);
    });
  });

  group('food sold as a whole unit', () {
    test('is always sellable, it has no ingredients to run out of', () {
      final result = AvailabilityCalculator.forMenuItem(
        const [],
        {},
        isIngredientTracked: false,
      );

      expect(result.canMakeAtLeastOne, isTrue);
      expect(result.isTracked, isFalse);
      // no stock behind it, so a servings count would be meaningless
      expect(result.hasServingLimit, isFalse);
    });

    test('is not treated as a drink missing its recipe', () {
      final untracked = AvailabilityCalculator.forMenuItem(
        const [],
        {},
        isIngredientTracked: false,
      );
      final trackedWithNoRecipe = AvailabilityCalculator.forMenuItem(
        const [],
        {},
      );

      // the same empty recipe, opposite outcomes, which is the whole point of
      // storing the distinction rather than inferring it
      expect(untracked.canMakeAtLeastOne, isTrue);
      expect(untracked.hasNoRecipe, isFalse);
      expect(trackedWithNoRecipe.canMakeAtLeastOne, isFalse);
      expect(trackedWithNoRecipe.hasNoRecipe, isTrue);
    });

    test('stays sellable even with a recipe and no stock', () {
      final result = AvailabilityCalculator.forMenuItem(
        [line(1, 'Milk', 200)],
        {},
        isIngredientTracked: false,
      );

      expect(result.canMakeAtLeastOne, isTrue);
    });
  });

  group('expired stock cannot cover an order', () {
    test('an item is blocked when all its stock has expired', () {
      // the repository hands over usable stock only, so expired stock reaches
      // the calculator in the expired map and nowhere else
      final result = AvailabilityCalculator.forMenuItemFromTotals(
        [line(1, 'Fresh Milk', 200)],
        const {},
        expiredByIngredient: const {1: 5000},
      );

      expect(result.canMakeAtLeastOne, isFalse);
      expect(result.blockedByExpiry, isTrue);
      expect(result.limitingIngredient, 'Fresh Milk');
    });

    test('an empty fridge is not reported as an expiry problem', () {
      final result = AvailabilityCalculator.forMenuItemFromTotals([
        line(1, 'Fresh Milk', 200),
      ], const {});

      expect(result.canMakeAtLeastOne, isFalse);
      // nothing expired, it simply ran out, and the till should say so
      expect(result.blockedByExpiry, isFalse);
    });

    test('expired stock alongside usable stock does not block the item', () {
      final result = AvailabilityCalculator.forMenuItemFromTotals(
        [line(1, 'Fresh Milk', 200)],
        const {1: 1000},
        expiredByIngredient: const {1: 5000},
      );

      // five litres have expired but there is still a litre that is fine
      expect(result.servings, 5);
      expect(result.blockedByExpiry, isFalse);
    });

    test(
      'the expiry reason names the ingredient that is actually blocking',
      () {
        final result = AvailabilityCalculator.forMenuItemFromTotals(
          [line(1, 'Espresso Beans', 18), line(2, 'Fresh Milk', 200)],
          const {1: 1000},
          expiredByIngredient: const {2: 2000},
        );

        // beans are fine, the milk has expired, so the milk is named
        expect(result.blockedByExpiry, isTrue);
        expect(result.limitingIngredient, 'Fresh Milk');
      },
    );
  });
  group('order reservation', () {
    // latte (item 1) and cappuccino (item 2) both use 200ml of milk (ingredient 1)
    final recipes = {
      1: [line(1, 'Milk', 200)],
      2: [line(1, 'Milk', 200)],
    };

    test('consumedByOrder multiplies recipe by quantity', () {
      final consumed = AvailabilityCalculator.consumedByOrder({1: 2}, recipes);

      expect(consumed[1], 400);
    });

    test('consumedByOrder adds up items sharing an ingredient', () {
      final consumed = AvailabilityCalculator.consumedByOrder({
        1: 2,
        2: 1,
      }, recipes);

      // 2 lattes + 1 cappuccino = 600ml of milk
      expect(consumed[1], 600);
    });

    test('an order already in progress shrinks what is still available', () {
      final totals = AvailabilityCalculator.totalsByIngredient({
        1: [stock(1, 500)],
      });

      // nothing ordered yet, 2 servings
      expect(
        AvailabilityCalculator.forMenuItemFromTotals(
          recipes[1]!,
          totals,
        ).servings,
        2,
      );

      // after 2 lattes are in the order there is no milk left for a cappuccino
      final left = AvailabilityCalculator.totalsAfterOrder(
        totals,
        AvailabilityCalculator.consumedByOrder({1: 2}, recipes),
      );
      final capp = AvailabilityCalculator.forMenuItemFromTotals(
        recipes[2]!,
        left,
      );

      expect(capp.servings, 0);
      expect(capp.limitingIngredient, 'Milk');
    });

    test('totalsAfterOrder never goes negative', () {
      final totals = AvailabilityCalculator.totalsByIngredient({
        1: [stock(1, 100)],
      });

      final left = AvailabilityCalculator.totalsAfterOrder(
        totals,
        AvailabilityCalculator.consumedByOrder({1: 5}, recipes),
      );

      expect(left[1], 0);
    });
  });
}
