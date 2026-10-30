import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/fefo_engine.dart';

void main() {
  // a fixed today, so the expiry rule is tested against a known date rather
  // than against whenever the suite happens to run
  final today = DateTime(2026, 10, 19);

  /// an expiry date [n] days from that fixed today, negative for the past
  String inDays(int n) {
    final d = today.add(Duration(days: n));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // helper so each test reads as a table of batches
  BatchStock b(int id, String expiry, double qty) =>
      BatchStock(batchId: id, expiryDate: expiry, quantityRemaining: qty);

  FefoPlan plan(List<BatchStock> batches, double needed) =>
      FefoEngine.plan(batches, needed, today: today);

  group('FefoEngine.plan', () {
    test('deduction fits in one batch', () {
      final result = plan([
        b(1, inDays(1), 1000),
        b(2, inDays(8), 1000),
      ], 200);

      expect(result.deductions.length, 1);
      expect(result.deductions[0].batchId, 1);
      expect(result.deductions[0].quantity, 200);
      expect(result.isFullyCovered, isTrue);
    });

    test('deduction splits across two batches', () {
      final result = plan([
        b(1, inDays(1), 150),
        b(2, inDays(8), 1000),
      ], 300);

      expect(result.deductions.length, 2);
      // batch 1 fully drained, remainder carried to batch 2
      expect(result.deductions[0].batchId, 1);
      expect(result.deductions[0].quantity, 150);
      expect(result.deductions[1].batchId, 2);
      expect(result.deductions[1].quantity, 150);
      expect(result.isFullyCovered, isTrue);
    });

    test('deduction splits across three or more batches', () {
      final result = plan([
        b(1, inDays(1), 100),
        b(2, inDays(2), 100),
        b(3, inDays(3), 100),
        b(4, inDays(4), 1000),
      ], 350);

      // proves the loop actually loops, not just one carry
      expect(result.deductions.length, 4);
      expect(result.deductions.map((d) => d.batchId), [1, 2, 3, 4]);
      expect(result.deductions.map((d) => d.quantity), [100, 100, 100, 50]);
      expect(result.isFullyCovered, isTrue);
    });

    test('stock runs out partway', () {
      final result = plan([
        b(1, inDays(1), 100),
        b(2, inDays(8), 50),
      ], 400);

      // takes everything there is and reports what's missing
      expect(result.deductions.length, 2);
      expect(result.deductions[0].quantity, 100);
      expect(result.deductions[1].quantity, 50);
      expect(result.shortfall, 250);
      expect(result.isFullyCovered, isFalse);
    });

    test('two batches, same expiry date → smaller quantity first', () {
      final result = plan([
        b(1, inDays(1), 1000),
        b(2, inDays(1), 300), // the partial carton
      ], 200);

      expect(result.deductions.length, 1);
      expect(result.deductions[0].batchId, 2);
    });

    test('input order does not matter, engine sorts itself', () {
      final result = plan([
        b(3, inDays(8), 1000),
        b(1, inDays(1), 1000),
        b(2, inDays(3), 1000),
      ], 100);

      expect(result.deductions[0].batchId, 1);
    });

    test('empty batches are skipped', () {
      final result = plan([
        b(1, inDays(1), 0), // earliest but empty
        b(2, inDays(8), 500),
      ], 100);

      expect(result.deductions.length, 1);
      expect(result.deductions[0].batchId, 2);
    });

    test('needing exactly a batch remainder drains it without touching the next',
        () {
      final result = plan([
        b(1, inDays(1), 200),
        b(2, inDays(8), 1000),
      ], 200);

      expect(result.deductions.length, 1);
      expect(result.deductions[0].quantity, 200);
      expect(result.isFullyCovered, isTrue);
    });

    test('no batches at all → everything is shortfall', () {
      final result = plan([], 100);

      expect(result.deductions, isEmpty);
      expect(result.shortfall, 100);
    });
  });

  group('FefoEngine.plan — expired stock', () {
    test('an expired batch is never deducted from', () {
      // without the expiry rule this is the worst case: sorting by soonest
      // expiry puts the expired carton first, so it would be used before
      // anything else rather than being left alone
      final result = plan([
        b(1, inDays(-1), 1000),
        b(2, inDays(8), 1000),
      ], 200);

      expect(result.deductions.length, 1);
      expect(result.deductions[0].batchId, 2);
      expect(result.isFullyCovered, isTrue);
    });

    test('a batch expiring today is still usable today', () {
      // the band is red and it needs using, but it has not expired yet
      final result = plan([
        b(1, inDays(0), 500),
        b(2, inDays(8), 1000),
      ], 200);

      expect(result.deductions[0].batchId, 1);
    });

    test('expired stock does not count toward covering the order', () {
      final result = plan([
        b(1, inDays(-3), 5000),
        b(2, inDays(8), 100),
      ], 400);

      // plenty on the shelf, but only 100 of it may be sold
      expect(result.deductions.length, 1);
      expect(result.deductions[0].quantity, 100);
      expect(result.shortfall, 300);
      expect(result.isFullyCovered, isFalse);
    });

    test('only expired stock means the sale cannot be covered at all', () {
      final result = plan([
        b(1, inDays(-1), 1000),
        b(2, inDays(-5), 1000),
      ], 200);

      expect(result.deductions, isEmpty);
      expect(result.shortfall, 200);
    });

    test('the same batches pass once the date is still within expiry', () {
      final batches = [b(1, inDays(-1), 1000)];

      // expired against today
      expect(FefoEngine.plan(batches, 200, today: today).isFullyCovered,
          isFalse);

      // the identical batch judged against an earlier date is fine, which
      // shows the rule is the date comparison and not something about the batch
      final earlier = today.subtract(const Duration(days: 5));
      expect(
        FefoEngine.plan(batches, 200, today: earlier).isFullyCovered,
        isTrue,
      );
    });
  });
}
