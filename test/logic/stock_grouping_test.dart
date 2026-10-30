import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/expiry_risk.dart';
import 'package:brewmanager/logic/stock_grouping.dart';
import 'package:brewmanager/models/inventory_batch.dart';

void main() {
  final today = DateTime(2026, 10, 13);

  String inDays(int n) {
    final d = today.add(Duration(days: n));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  BatchWithIngredient batch({
    required int batchId,
    required int ingredientId,
    required String name,
    required String unit,
    required int expiresInDays,
    required double remaining,
    double capacity = 1000,
  }) {
    return BatchWithIngredient(
      batch: InventoryBatch(
        batchId: batchId,
        ingredientId: ingredientId,
        expiryDate: inDays(expiresInDays),
        containerCapacity: capacity,
        containersReceived: 1,
        quantityRemaining: remaining,
        receivedAt: '2026-10-01T08:00:00',
      ),
      ingredientName: name,
      unitOfMeasure: unit,
    );
  }

  group('StockGrouping.byIngredient', () {
    test('batches of one ingredient end up in one group', () {
      final groups = StockGrouping.byIngredient([
        batch(
          batchId: 1,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 10,
          remaining: 1000,
        ),
        batch(
          batchId: 2,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 2,
          remaining: 150,
        ),
      ], today);

      expect(groups.length, 1);
      expect(groups.first.batchCount, 2);
      expect(groups.first.ingredientName, 'Fresh Milk');
      expect(groups.first.unitOfMeasure, 'ml');
    });

    test('the total is every batch added up', () {
      final groups = StockGrouping.byIngredient([
        batch(
          batchId: 1,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 10,
          remaining: 1000,
        ),
        batch(
          batchId: 2,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 2,
          remaining: 150,
        ),
        batch(
          batchId: 3,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 4,
          remaining: 200,
        ),
      ], today);

      expect(groups.first.totalQuantity, 1350);
    });

    test('inside a group the soonest expiry comes first, which is fefo order',
        () {
      final groups = StockGrouping.byIngredient([
        batch(
          batchId: 1,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 10,
          remaining: 1000,
        ),
        batch(
          batchId: 2,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 2,
          remaining: 150,
        ),
        batch(
          batchId: 3,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 4,
          remaining: 200,
        ),
      ], today);

      expect(
        groups.first.batches.map((b) => b.batch.batchId),
        [2, 3, 1],
      );
    });

    test('groups are alphabetical, not urgency ordered', () {
      final groups = StockGrouping.byIngredient([
        // milk is the urgent one but beans still sorts first
        batch(
          batchId: 1,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 1,
          remaining: 500,
        ),
        batch(
          batchId: 2,
          ingredientId: 20,
          name: 'Espresso Beans',
          unit: 'g',
          expiresInDays: 30,
          remaining: 1000,
        ),
        batch(
          batchId: 3,
          ingredientId: 30,
          name: 'Chocolate Syrup',
          unit: 'ml',
          expiresInDays: 6,
          remaining: 750,
        ),
      ], today);

      expect(
        groups.map((g) => g.ingredientName),
        ['Chocolate Syrup', 'Espresso Beans', 'Fresh Milk'],
      );
    });

    test('the group takes the band of its most urgent batch', () {
      final groups = StockGrouping.byIngredient([
        batch(
          batchId: 1,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 30,
          remaining: 1000,
        ),
        batch(
          batchId: 2,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 1,
          remaining: 150,
        ),
      ], today);

      // one green batch and one red, the header has to show red
      expect(groups.first.worstBand, ExpiryBand.red);
    });

    test('a group with nothing urgent stays green', () {
      final groups = StockGrouping.byIngredient([
        batch(
          batchId: 1,
          ingredientId: 10,
          name: 'Fresh Milk',
          unit: 'ml',
          expiresInDays: 30,
          remaining: 1000,
        ),
      ], today);

      expect(groups.first.worstBand, ExpiryBand.green);
    });

    test('no batches gives no groups', () {
      expect(StockGrouping.byIngredient([], today), isEmpty);
    });
  });
}
