import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/models/inventory_batch.dart';

void main() {
  /// a batch holding [remaining] across containers of [capacity]
  BatchWithIngredient batch({
    required double capacity,
    required int received,
    required double remaining,
  }) {
    return BatchWithIngredient(
      batch: InventoryBatch(
        batchId: 1,
        ingredientId: 1,
        expiryDate: '2026-12-01',
        containerCapacity: capacity,
        containersReceived: received,
        quantityRemaining: remaining,
        receivedAt: '2026-10-01T08:00:00',
      ),
      ingredientName: 'Fresh Milk',
      unitOfMeasure: 'ml',
    );
  }

  group('what the records imply is on the shelf', () {
    test('a part used batch is whole containers plus the opened one', () {
      // 1400ml across 1000ml cartons: one sealed, one opened with 400 in it
      final b = batch(capacity: 1000, received: 2, remaining: 1400);

      expect(b.impliedSealedCount, 1);
      expect(b.impliedOpenedRemainder, 400);
      expect(b.hasOpenedContainer, isTrue);
    });

    test('an exact multiple is all sealed, nothing opened', () {
      final b = batch(capacity: 1000, received: 2, remaining: 2000);

      expect(b.impliedSealedCount, 2);
      expect(b.impliedOpenedRemainder, 0);
      expect(b.hasOpenedContainer, isFalse);
    });

    test('less than one container is just the opened one', () {
      final b = batch(capacity: 1000, received: 1, remaining: 400);

      expect(b.impliedSealedCount, 0);
      expect(b.impliedOpenedRemainder, 400);
      expect(b.hasOpenedContainer, isTrue);
    });

    test('an empty batch implies nothing on the shelf', () {
      final b = batch(capacity: 1000, received: 1, remaining: 0);

      expect(b.impliedSealedCount, 0);
      expect(b.impliedOpenedRemainder, 0);
      expect(b.hasOpenedContainer, isFalse);
    });

    test('works with a container size that is not round', () {
      // 1875ml of 750ml bottles: two sealed and 375 left in the opened one
      final b = batch(capacity: 750, received: 3, remaining: 1875);

      expect(b.impliedSealedCount, 2);
      expect(b.impliedOpenedRemainder, 375);
    });

    test('never claims more sealed containers than were received', () {
      // a corrected or mis-entered batch could hold more than it ever received,
      // the inference must not invent containers that cannot exist
      final b = batch(capacity: 1000, received: 2, remaining: 5000);

      expect(b.impliedSealedCount, 2);
    });

    test('a total just short of a multiple still reads as all sealed', () {
      // repeated deductions leave values like 1999.9999999998, and flooring
      // that lands one container short, describing a nearly full sealed carton
      // as an opened one with 999.99 in it
      final b = batch(
        capacity: 1000,
        received: 2,
        remaining: 2000 - 0.0000001,
      );

      expect(b.impliedSealedCount, 2);
      expect(b.hasOpenedContainer, isFalse);
      expect(b.impliedOpenedRemainder, 0);
    });

    test('a sliver left over is not an opened container', () {
      final b = batch(
        capacity: 1000,
        received: 2,
        remaining: 1000 + 0.0000001,
      );

      expect(b.impliedSealedCount, 1);
      expect(b.hasOpenedContainer, isFalse);
    });
  });
}
