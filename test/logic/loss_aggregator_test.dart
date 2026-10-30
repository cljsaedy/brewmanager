import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/loss_aggregator.dart';
import 'package:brewmanager/models/ingredient.dart';
import 'package:brewmanager/models/loss_record.dart';

void main() {
  LossRecord record({
    required String day,
    required int ingredientId,
    required String name,
    required String unit,
    required LossCategory category,
    required double quantity,
    double capacity = 1000,
  }) {
    return LossRecord(
      occurredAt: DateTime.parse('${day}T10:00:00'),
      ingredientId: ingredientId,
      ingredientName: name,
      unitOfMeasure: unit,
      category: category,
      quantity: quantity,
      containersEquivalent: quantity / capacity,
    );
  }

  group('LossAggregator.hasMixedUnits', () {
    test('one unit is not mixed', () {
      final mixed = LossAggregator.hasMixedUnits([
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 1000,
        ),
      ]);
      expect(mixed, isFalse);
    });

    test('ml and g together are mixed', () {
      final mixed = LossAggregator.hasMixedUnits([
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 1000,
        ),
        record(
          day: '2026-10-01',
          ingredientId: 2,
          name: 'Espresso Beans',
          unit: 'g',
          category: LossCategory.unexplained,
          quantity: 500,
        ),
      ]);
      expect(mixed, isTrue);
    });

    test('no records is not mixed', () {
      expect(LossAggregator.hasMixedUnits([]), isFalse);
    });
  });

  group('LossAggregator.byIngredient', () {
    test('sums each category separately', () {
      final bars = LossAggregator.byIngredient([
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 1000,
        ),
        record(
          day: '2026-10-02',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 500,
        ),
        record(
          day: '2026-10-02',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.unexplained,
          quantity: 250,
        ),
      ]);

      expect(bars.length, 1);
      expect(bars.first.declared, 1500);
      expect(bars.first.unexplained, 250);
      expect(bars.first.total, 1750);
      // single unit, so the real unit is kept
      expect(bars.first.unit, 'ml');
    });

    test('mixed units switch to containers so the axis means something', () {
      final bars = LossAggregator.byIngredient([
        // one whole 1000ml carton of milk
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 1000,
        ),
        // half a 1000g bag of beans
        record(
          day: '2026-10-01',
          ingredientId: 2,
          name: 'Espresso Beans',
          unit: 'g',
          category: LossCategory.unexplained,
          quantity: 500,
        ),
      ]);

      final milk = bars.firstWhere((b) => b.label == 'Fresh Milk');
      final beans = bars.firstWhere((b) => b.label == 'Espresso Beans');

      expect(milk.declared, 1.0);
      expect(beans.unexplained, 0.5);
      expect(milk.unit, 'containers');
      expect(beans.unit, 'containers');
    });

    test('biggest loss comes first', () {
      final bars = LossAggregator.byIngredient([
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 100,
        ),
        record(
          day: '2026-10-01',
          ingredientId: 2,
          name: 'Chocolate Syrup',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 900,
        ),
      ]);

      expect(bars.first.label, 'Chocolate Syrup');
    });

    test('no records gives no bars', () {
      expect(LossAggregator.byIngredient([]), isEmpty);
    });
  });

  group('LossAggregator.byDay', () {
    test('groups by day in date order', () {
      final bars = LossAggregator.byDay([
        record(
          day: '2026-10-03',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.unexplained,
          quantity: 300,
        ),
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 1000,
        ),
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.unexplained,
          quantity: 200,
        ),
      ]);

      expect(bars.length, 2);
      // earliest first
      expect(bars.first.sortKey, '2026-10-01');
      expect(bars.first.declared, 1000);
      expect(bars.first.unexplained, 200);
      expect(bars.last.sortKey, '2026-10-03');
      expect(bars.last.unexplained, 300);
    });

    test('the axis label drops the year to stay narrow', () {
      final bars = LossAggregator.byDay([
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 100,
        ),
      ]);

      expect(bars.first.label, '10-01');
    });
  });

  group('LossAggregator.summary', () {
    test('keeps each ingredient in its own unit', () {
      final rows = LossAggregator.summary([
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 1000,
        ),
        record(
          day: '2026-10-01',
          ingredientId: 2,
          name: 'Espresso Beans',
          unit: 'g',
          category: LossCategory.unexplained,
          quantity: 500,
        ),
      ]);

      final milk = rows.firstWhere((r) => r.ingredientName == 'Fresh Milk');
      final beans = rows.firstWhere(
        (r) => r.ingredientName == 'Espresso Beans',
      );

      // real quantities, not containers, so the exact figures are always available
      expect(milk.declared, 1000);
      expect(milk.unitOfMeasure, 'ml');
      expect(beans.unexplained, 500);
      expect(beans.unitOfMeasure, 'g');
    });

    test('rows are in name order', () {
      final rows = LossAggregator.summary([
        record(
          day: '2026-10-01',
          ingredientId: 1,
          name: 'Fresh Milk',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 10,
        ),
        record(
          day: '2026-10-01',
          ingredientId: 2,
          name: 'Caramel Syrup',
          unit: 'ml',
          category: LossCategory.declared,
          quantity: 10,
        ),
      ]);

      expect(rows.map((r) => r.ingredientName), [
        'Caramel Syrup',
        'Fresh Milk',
      ]);
    });
  });

  group('LossAggregator.ranked', () {
    Ingredient ing(int id, String name, String unit) => Ingredient(
      ingredientId: id,
      name: name,
      unitOfMeasure: unit,
      isArchived: false,
    );

    final ingredients = [
      ing(1, 'Fresh Milk', 'ml'),
      ing(2, 'Espresso Beans', 'g'),
      ing(3, 'Caramel Syrup', 'ml'),
    ];

    test('only the asked for category is counted', () {
      final rows = LossAggregator.ranked(
        records: [
          record(
            day: '2026-10-01',
            ingredientId: 1,
            name: 'Fresh Milk',
            unit: 'ml',
            category: LossCategory.declared,
            quantity: 1000,
          ),
          record(
            day: '2026-10-01',
            ingredientId: 1,
            name: 'Fresh Milk',
            unit: 'ml',
            category: LossCategory.unexplained,
            quantity: 250,
          ),
        ],
        category: LossCategory.unexplained,
        ingredients: ingredients,
      );

      final milk = rows.firstWhere((r) => r.ingredientId == 1);
      expect(milk.quantity, 250);
    });

    test('ranks by container equivalent, not by the raw amount', () {
      final rows = LossAggregator.ranked(
        records: [
          // 600g of 1000g bags is more than half a container
          record(
            day: '2026-10-01',
            ingredientId: 2,
            name: 'Espresso Beans',
            unit: 'g',
            category: LossCategory.unexplained,
            quantity: 600,
            capacity: 1000,
          ),
          // 900ml of 1000ml cartons is a bigger share despite similar numbers
          record(
            day: '2026-10-01',
            ingredientId: 1,
            name: 'Fresh Milk',
            unit: 'ml',
            category: LossCategory.unexplained,
            quantity: 900,
            capacity: 1000,
          ),
        ],
        category: LossCategory.unexplained,
        ingredients: ingredients,
      );

      expect(rows.first.ingredientName, 'Fresh Milk');
      expect(rows.first.containers, 0.9);
      expect(rows[1].ingredientName, 'Espresso Beans');
    });

    test(
      'a smaller amount can outrank a bigger one in a smaller container',
      () {
        final rows = LossAggregator.ranked(
          records: [
            // 1000ml of milk is one whole carton
            record(
              day: '2026-10-01',
              ingredientId: 1,
              name: 'Fresh Milk',
              unit: 'ml',
              category: LossCategory.unexplained,
              quantity: 1000,
              capacity: 1000,
            ),
            // 600ml of syrup is most of a 750ml bottle, so it ranks below one
            // whole carton but the raw numbers alone would not say so
            record(
              day: '2026-10-01',
              ingredientId: 3,
              name: 'Caramel Syrup',
              unit: 'ml',
              category: LossCategory.unexplained,
              quantity: 600,
              capacity: 750,
            ),
          ],
          category: LossCategory.unexplained,
          ingredients: ingredients,
        );

        expect(rows.first.ingredientName, 'Fresh Milk');
        expect(rows.first.containers, 1.0);
        expect(rows[1].containers, closeTo(0.8, 1e-9));
      },
    );

    test('ingredients with no loss stay in the list as zero rows', () {
      final rows = LossAggregator.ranked(
        records: [
          record(
            day: '2026-10-01',
            ingredientId: 1,
            name: 'Fresh Milk',
            unit: 'ml',
            category: LossCategory.unexplained,
            quantity: 250,
          ),
        ],
        category: LossCategory.unexplained,
        ingredients: ingredients,
      );

      // all three appear, so an ingredient with no loss is visibly fine rather
      // than looking as though it was left out of the report
      expect(rows.length, 3);
      expect(rows.where((r) => r.isZero).length, 2);
    });

    test('zero rows are ordered by name so the list is stable', () {
      final rows = LossAggregator.ranked(
        records: const [],
        category: LossCategory.unexplained,
        ingredients: ingredients,
      );

      expect(rows.map((r) => r.ingredientName), [
        'Caramel Syrup',
        'Espresso Beans',
        'Fresh Milk',
      ]);
    });

    test('an archived ingredient still appears if it has historical loss', () {
      final rows = LossAggregator.ranked(
        records: [
          record(
            day: '2026-10-01',
            ingredientId: 99,
            name: 'Discontinued Syrup',
            unit: 'ml',
            category: LossCategory.unexplained,
            quantity: 500,
          ),
        ],
        category: LossCategory.unexplained,
        // not in the active list any more
        ingredients: ingredients,
      );

      expect(rows.first.ingredientName, 'Discontinued Syrup');
      expect(rows.length, 4);
    });
  });

  group('LossAggregator.needsAttention', () {
    Ingredient ing(int id, String name, String unit) => Ingredient(
      ingredientId: id,
      name: name,
      unitOfMeasure: unit,
      isArchived: false,
    );

    final ingredients = [ing(1, 'Fresh Milk', 'ml'), ing(2, 'Beans', 'g')];

    test('picks the worst unexplained loss', () {
      final worst = LossAggregator.needsAttention(
        records: [
          record(
            day: '2026-10-01',
            ingredientId: 1,
            name: 'Fresh Milk',
            unit: 'ml',
            category: LossCategory.unexplained,
            quantity: 300,
          ),
          record(
            day: '2026-10-01',
            ingredientId: 2,
            name: 'Beans',
            unit: 'g',
            category: LossCategory.unexplained,
            quantity: 800,
          ),
        ],
        ingredients: ingredients,
      );

      expect(worst!.ingredientName, 'Beans');
    });

    test('ignores reported losses, those are already explained', () {
      final worst = LossAggregator.needsAttention(
        records: [
          record(
            day: '2026-10-01',
            ingredientId: 1,
            name: 'Fresh Milk',
            unit: 'ml',
            category: LossCategory.declared,
            quantity: 5000,
          ),
        ],
        ingredients: ingredients,
      );

      // a dropped carton points at an incident, not at something to change
      expect(worst, isNull);
    });

    test('nothing to report when there is no unexplained loss', () {
      final worst = LossAggregator.needsAttention(
        records: const [],
        ingredients: ingredients,
      );

      expect(worst, isNull);
    });
  });
}
