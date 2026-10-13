import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/loss_aggregator.dart';
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
      final beans = rows.firstWhere((r) => r.ingredientName == 'Espresso Beans');

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

      expect(rows.map((r) => r.ingredientName), ['Caramel Syrup', 'Fresh Milk']);
    });
  });
}
