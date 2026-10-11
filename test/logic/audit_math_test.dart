import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/audit_math.dart';

void main() {
  group('AuditMath.auditedQuantity', () {
    test('sealed containers only', () {
      final q = AuditMath.auditedQuantity(
        const AuditEntry(sealedCount: 3, openedTotal: 0),
        1000,
      );
      expect(q, 3000);
    });

    test('sealed plus a part used container', () {
      // 2 sealed 1000ml cartons plus half a carton open = 2500
      final q = AuditMath.auditedQuantity(
        const AuditEntry(sealedCount: 2, openedTotal: 0.5),
        1000,
      );
      expect(q, 2500);
    });

    test('opened total above 1, which the control must allow', () {
      // three cartons open holding 1¾ between them, nothing sealed
      final q = AuditMath.auditedQuantity(
        const AuditEntry(sealedCount: 0, openedTotal: 1.75),
        1000,
      );
      expect(q, 1750);
    });

    test('nothing left counts as zero', () {
      final q = AuditMath.auditedQuantity(
        const AuditEntry(sealedCount: 0, openedTotal: 0),
        1000,
      );
      expect(q, 0);
    });

    test('works with a non round container size', () {
      final q = AuditMath.auditedQuantity(
        const AuditEntry(sealedCount: 1, openedTotal: 0.25),
        750,
      );
      expect(q, 937.5);
    });
  });

  group('AuditMath.variance', () {
    test('counted more than expected is a surplus', () {
      expect(AuditMath.variance(2000, 1500), 500);
    });

    test('counted less than expected is a deficit', () {
      expect(AuditMath.variance(1500, 2000), -500);
    });

    test('a perfect count is exactly zero', () {
      expect(AuditMath.variance(1500, 1500), 0);
    });

    test('float noise is clamped to zero', () {
      // 0.1 × 3 is not exactly 0.3 in binary floating point
      final theoretical = 0.1 * 3;
      expect(AuditMath.variance(0.3, theoretical), 0);
    });
  });

  group('AuditMath.startingEntry', () {
    test('a batch never audited before starts at nothing', () {
      final entry = AuditMath.startingEntry(null, 1000);
      expect(entry.sealedCount, 0);
      expect(entry.openedTotal, 0);
    });

    test('whole containers come back as sealed', () {
      final entry = AuditMath.startingEntry(3000, 1000);
      expect(entry.sealedCount, 3);
      expect(entry.openedTotal, 0);
    });

    test('a remainder comes back as the opened total', () {
      final entry = AuditMath.startingEntry(2500, 1000);
      expect(entry.sealedCount, 2);
      expect(entry.openedTotal, 0.5);
    });

    test('the split may differ from last time but the total is identical', () {
      // last shift entered sealed 2 + opened 1.25 = 3.25 containers = 3250
      final entry = AuditMath.startingEntry(3250, 1000);
      // comes back split differently
      expect(entry.sealedCount, 3);
      expect(entry.openedTotal, 0.25);
      // but the same total, which is what the control is restoring
      expect(entry.totalContainers, 3.25);
    });

    test('an odd remainder snaps onto a quarter step', () {
      // 2600 of 1000 is 2.6 containers, the control can only sit on quarters
      final entry = AuditMath.startingEntry(2600, 1000);
      expect(entry.sealedCount, 2);
      expect(entry.openedTotal, 0.5);
    });
  });

  group('AuditMath.roundToStep', () {
    test('snaps to the nearest quarter', () {
      // 0.12 really is nearer 0 than 0.25, so it rounds down
      expect(AuditMath.roundToStep(0.12), 0);
      expect(AuditMath.roundToStep(0.13), 0.25);
      expect(AuditMath.roundToStep(0.3), 0.25);
      expect(AuditMath.roundToStep(0.4), 0.5);
      expect(AuditMath.roundToStep(0.9), 1.0);
    });

    test('never goes below zero', () {
      expect(AuditMath.roundToStep(-5), 0);
    });
  });

  group('AuditMath.containersPossible and isImpossibleCount', () {
    test('received minus declared losses', () {
      expect(
        AuditMath.containersPossible(containersReceived: 5, containersLost: 2),
        3,
      );
    });

    test('never negative even if losses somehow exceed receipts', () {
      expect(
        AuditMath.containersPossible(containersReceived: 1, containersLost: 3),
        0,
      );
    });

    test('a sealed count within the possible total is fine', () {
      expect(
        AuditMath.isImpossibleCount(sealedCount: 3, containersPossible: 3),
        isFalse,
      );
    });

    test('a sealed count above the possible total is impossible', () {
      // more sealed cartons on the shelf than were ever recorded as received
      expect(
        AuditMath.isImpossibleCount(sealedCount: 4, containersPossible: 3),
        isTrue,
      );
    });
  });
}
