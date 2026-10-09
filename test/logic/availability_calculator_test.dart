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
          1: [stock(1, 500)]
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
          1: [stock(1, 150), stock(2, 150), stock(3, 150)]
        },
      );

      // 450 total / 200 = 2
      expect(result.servings, 2);
    });

    test('missing ingredient stock means zero servings and names the blocker',
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
    });

    test('a menu item with no recipe is unsellable, not unlimited', () {
      final result = AvailabilityCalculator.forMenuItem([], {});

      expect(result.servings, 0);
      expect(result.hasNoRecipe, isTrue);
    });

    test('no limiting ingredient is named when stock is fine', () {
      final result = AvailabilityCalculator.forMenuItem(
        [line(1, 'Milk', 200)],
        {
          1: [stock(1, 1000)]
        },
      );

      expect(result.servings, 5);
      expect(result.limitingIngredient, isNull);
    });
  });

  group('order reservation', () {
    // latte (item 1) and cappuccino (item 2) both use 200ml of milk (ingredient 1)
    final recipes = {
      1: [line(1, 'Milk', 200)],
      2: [line(1, 'Milk', 200)],
    };

    test('consumedByOrder multiplies recipe by quantity', () {
      final consumed = AvailabilityCalculator.consumedByOrder(
        {1: 2},
        recipes,
      );

      expect(consumed[1], 400);
    });

    test('consumedByOrder adds up items sharing an ingredient', () {
      final consumed = AvailabilityCalculator.consumedByOrder(
        {1: 2, 2: 1},
        recipes,
      );

      // 2 lattes + 1 cappuccino = 600ml of milk
      expect(consumed[1], 600);
    });

    test('an order already in progress shrinks what is still available', () {
      final totals = AvailabilityCalculator.totalsByIngredient({
        1: [stock(1, 500)]
      });

      // nothing ordered yet, 2 servings
      expect(
        AvailabilityCalculator.forMenuItemFromTotals(recipes[1]!, totals)
            .servings,
        2,
      );

      // after 2 lattes are in the order there is no milk left for a cappuccino
      final left = AvailabilityCalculator.totalsAfterOrder(
        totals,
        AvailabilityCalculator.consumedByOrder({1: 2}, recipes),
      );
      final capp =
          AvailabilityCalculator.forMenuItemFromTotals(recipes[2]!, left);

      expect(capp.servings, 0);
      expect(capp.limitingIngredient, 'Milk');
    });

    test('totalsAfterOrder never goes negative', () {
      final totals = AvailabilityCalculator.totalsByIngredient({
        1: [stock(1, 100)]
      });

      final left = AvailabilityCalculator.totalsAfterOrder(
        totals,
        AvailabilityCalculator.consumedByOrder({1: 5}, recipes),
      );

      expect(left[1], 0);
    });
  });
}
