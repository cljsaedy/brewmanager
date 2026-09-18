import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/fefo_engine.dart';

void main() {
  // helper so each test reads as a table of batches
  BatchStock b(int id, String expiry, double qty) =>
      BatchStock(batchId: id, expiryDate: expiry, quantityRemaining: qty);

  group('FefoEngine.plan', () {
    test('deduction fits in one batch', () {
      final plan = FefoEngine.plan([
        b(1, '2026-09-20', 1000),
        b(2, '2026-09-27', 1000),
      ], 200);

      expect(plan.deductions.length, 1);
      expect(plan.deductions[0].batchId, 1);
      expect(plan.deductions[0].quantity, 200);
      expect(plan.isFullyCovered, isTrue);
    });

    test('deduction splits across two batches', () {
      final plan = FefoEngine.plan([
        b(1, '2026-09-20', 150),
        b(2, '2026-09-27', 1000),
      ], 300);

      expect(plan.deductions.length, 2);
      // batch 1 fully drained, remainder carried to batch 2
      expect(plan.deductions[0].batchId, 1);
      expect(plan.deductions[0].quantity, 150);
      expect(plan.deductions[1].batchId, 2);
      expect(plan.deductions[1].quantity, 150);
      expect(plan.isFullyCovered, isTrue);
    });

    test('deduction splits across three or more batches', () {
      final plan = FefoEngine.plan([
        b(1, '2026-09-20', 100),
        b(2, '2026-09-21', 100),
        b(3, '2026-09-22', 100),
        b(4, '2026-09-23', 1000),
      ], 350);

      // proves the loop actually loops, not just one carry
      expect(plan.deductions.length, 4);
      expect(plan.deductions.map((d) => d.batchId), [1, 2, 3, 4]);
      expect(plan.deductions.map((d) => d.quantity), [100, 100, 100, 50]);
      expect(plan.isFullyCovered, isTrue);
    });

    test('stock runs out partway', () {
      final plan = FefoEngine.plan([
        b(1, '2026-09-20', 100),
        b(2, '2026-09-27', 50),
      ], 400);

      // takes everything there is and reports what's missing
      expect(plan.deductions.length, 2);
      expect(plan.deductions[0].quantity, 100);
      expect(plan.deductions[1].quantity, 50);
      expect(plan.shortfall, 250);
      expect(plan.isFullyCovered, isFalse);
    });

    test('two batches, same expiry date → smaller quantity first', () {
      final plan = FefoEngine.plan([
        b(1, '2026-09-20', 1000),
        b(2, '2026-09-20', 300), // the partial carton
      ], 200);

      expect(plan.deductions.length, 1);
      expect(plan.deductions[0].batchId, 2);
    });

    // extras beyond the five required

    test('input order does not matter, engine sorts itself', () {
      final plan = FefoEngine.plan([
        b(3, '2026-09-27', 1000),
        b(1, '2026-09-20', 1000),
        b(2, '2026-09-22', 1000),
      ], 100);

      expect(plan.deductions[0].batchId, 1);
    });

    test('empty batches are skipped', () {
      final plan = FefoEngine.plan([
        b(1, '2026-09-20', 0), // earliest but empty
        b(2, '2026-09-27', 500),
      ], 100);

      expect(plan.deductions.length, 1);
      expect(plan.deductions[0].batchId, 2);
    });

    test('needing exactly a batch remainder drains it without touching the next',
        () {
      final plan = FefoEngine.plan([
        b(1, '2026-09-20', 200),
        b(2, '2026-09-27', 1000),
      ], 200);

      expect(plan.deductions.length, 1);
      expect(plan.deductions[0].quantity, 200);
      expect(plan.isFullyCovered, isTrue);
    });

    test('no batches at all → everything is shortfall', () {
      final plan = FefoEngine.plan([], 100);

      expect(plan.deductions, isEmpty);
      expect(plan.shortfall, 100);
    });
  });
}
