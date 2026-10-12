import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/audit_math.dart';
import 'package:brewmanager/logic/rotation_break_detector.dart';
import 'package:brewmanager/models/audit_batch.dart';
import 'package:brewmanager/models/inventory_batch.dart';

void main() {
  /// builds a finished audit result with a given variance, so each case reads as a table
  AuditResult result({
    required int batchId,
    required int ingredientId,
    required String ingredientName,
    required double theoretical,
    required double audited,
    double capacity = 1000,
    String varianceType = VarianceType.unexplained,
  }) {
    final batch = BatchWithIngredient(
      batch: InventoryBatch(
        batchId: batchId,
        ingredientId: ingredientId,
        expiryDate: '2026-12-01',
        containerCapacity: capacity,
        containersReceived: 5,
        quantityRemaining: theoretical,
        receivedAt: '2026-10-01T08:00:00',
      ),
      ingredientName: ingredientName,
      unitOfMeasure: 'ml',
    );

    return AuditResult(
      auditBatch: AuditBatch(
        batch: batch,
        theoreticalQuantity: theoretical,
        containersPossible: 5,
        startingEntry: const AuditEntry(sealedCount: 0, openedTotal: 0),
      ),
      entry: const AuditEntry(sealedCount: 0, openedTotal: 0),
      auditedQuantity: audited,
      variance: AuditMath.variance(audited, theoretical),
      varianceType: varianceType,
    );
  }

  group('RotationBreakDetector.detect', () {
    test('the spec example is flagged', () {
      // batch A +500, batch B -500, same ingredient
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 2000,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1500,
        ),
      ]);

      expect(breaks.length, 1);
      expect(breaks.first.ingredientName, 'Fresh Milk');
      expect(breaks.first.surplus.auditBatch.batchId, 1);
      expect(breaks.first.deficit.auditBatch.batchId, 2);
      expect(breaks.first.amountMoved, 500);
    });

    test('variances that nearly cancel are still flagged', () {
      // +500 and -480, a realistic count rather than a perfect one
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 2000,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1520,
        ),
      ]);

      expect(breaks.length, 1);
    });

    test('a real loss alongside a small surplus is not a rotation break', () {
      // +100 and -1000 do not cancel, something was genuinely lost
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 1600,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1000,
        ),
      ]);

      expect(breaks, isEmpty);
    });

    test('cancelling variances on different ingredients are not a pair', () {
      // milk up 500, beans down 500, unrelated
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 2000,
        ),
        result(
          batchId: 2,
          ingredientId: 20,
          ingredientName: 'Espresso Beans',
          theoretical: 2000,
          audited: 1500,
        ),
      ]);

      expect(breaks, isEmpty);
    });

    test('two deficits are not a rotation break', () {
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 1000,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1500,
        ),
      ]);

      expect(breaks, isEmpty);
    });

    test('tiny cancelling variances are treated as measurement slop', () {
      // +10 and -10 on 1000ml containers is below the 5% noise floor
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 1510,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1990,
        ),
      ]);

      expect(breaks, isEmpty);
    });

    test('an unrecorded delivery is never treated as misrotation', () {
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 2000,
          varianceType: VarianceType.unrecordedReceiving,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1500,
        ),
      ]);

      expect(breaks, isEmpty);
    });

    test('exact counts produce nothing to flag', () {
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1500,
          audited: 1500,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 2000,
        ),
      ]);

      expect(breaks, isEmpty);
    });

    test('each batch belongs to at most one pair', () {
      // one big surplus and two deficits that could each cancel it
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1000,
          audited: 1500,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1500,
        ),
        result(
          batchId: 3,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1510,
        ),
      ]);

      // only one pair, the closest cancelling match
      expect(breaks.length, 1);
      expect(breaks.first.deficit.auditBatch.batchId, 2);
    });

    test('two separate pairs on the same ingredient are both found', () {
      final breaks = RotationBreakDetector.detect([
        result(
          batchId: 1,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1000,
          audited: 2000,
        ),
        result(
          batchId: 2,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 2000,
          audited: 1000,
        ),
        result(
          batchId: 3,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1000,
          audited: 1300,
        ),
        result(
          batchId: 4,
          ingredientId: 10,
          ingredientName: 'Fresh Milk',
          theoretical: 1000,
          audited: 700,
        ),
      ]);

      expect(breaks.length, 2);
    });
  });
}
