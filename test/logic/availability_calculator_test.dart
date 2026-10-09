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
}
