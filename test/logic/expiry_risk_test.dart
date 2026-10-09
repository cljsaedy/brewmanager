import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/expiry_risk.dart';

void main() {
  // fixed "today" so these never depend on when the tests are run
  final today = DateTime(2026, 10, 9);

  // expiry date N days from that fixed today
  String inDays(int n) {
    final d = today.add(Duration(days: n));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  group('ExpiryRisk.bandFor', () {
    test('already expired is red', () {
      expect(ExpiryRisk.bandFor(inDays(-5), today), ExpiryBand.red);
      expect(ExpiryRisk.bandFor(inDays(-1), today), ExpiryBand.red);
    });

    test('today, tomorrow and 2 days are red (the 48h band)', () {
      expect(ExpiryRisk.bandFor(inDays(0), today), ExpiryBand.red);
      expect(ExpiryRisk.bandFor(inDays(1), today), ExpiryBand.red);
      expect(ExpiryRisk.bandFor(inDays(2), today), ExpiryBand.red);
    });

    test('3 to 7 days is yellow', () {
      expect(ExpiryRisk.bandFor(inDays(3), today), ExpiryBand.yellow);
      expect(ExpiryRisk.bandFor(inDays(7), today), ExpiryBand.yellow);
    });

    test('more than 7 days is green', () {
      expect(ExpiryRisk.bandFor(inDays(8), today), ExpiryBand.green);
      expect(ExpiryRisk.bandFor(inDays(90), today), ExpiryBand.green);
    });

    test('band scores match the suggestion weighting in the spec', () {
      expect(ExpiryBand.red.score, 1.0);
      expect(ExpiryBand.yellow.score, 0.5);
      expect(ExpiryBand.green.score, 0.0);
    });

    test('time of day does not change the band', () {
      // same calendar day but nearly midnight, must still be red for today
      final lateToday = DateTime(2026, 10, 9, 23, 59);
      expect(ExpiryRisk.bandFor(inDays(0), lateToday), ExpiryBand.red);
      // and a batch 8 days out stays green whatever the hour
      expect(ExpiryRisk.bandFor(inDays(8), lateToday), ExpiryBand.green);
    });
  });

  group('ExpiryRisk.daysUntil and isExpired', () {
    test('counts whole days both ways', () {
      expect(ExpiryRisk.daysUntil(inDays(5), today), 5);
      expect(ExpiryRisk.daysUntil(inDays(0), today), 0);
      expect(ExpiryRisk.daysUntil(inDays(-3), today), -3);
    });

    test('expiring today is not yet expired', () {
      expect(ExpiryRisk.isExpired(inDays(0), today), isFalse);
      expect(ExpiryRisk.isExpired(inDays(-1), today), isTrue);
    });
  });

  group('ExpiryRisk.describe', () {
    test('wording for past, today, tomorrow and later', () {
      expect(ExpiryRisk.describe(inDays(-2), today), 'expired 2 days ago');
      expect(ExpiryRisk.describe(inDays(-1), today), 'expired 1 day ago');
      expect(ExpiryRisk.describe(inDays(0), today), 'expires today');
      expect(ExpiryRisk.describe(inDays(1), today), 'expires tomorrow');
      expect(ExpiryRisk.describe(inDays(6), today), 'expires in 6 days');
    });
  });
}
