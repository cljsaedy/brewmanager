import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/clock_guard.dart';

void main() {
  final recorded = DateTime(2026, 10, 9, 14, 0);

  group('ClockGuard.check', () {
    test('no recorded activity yet means no warning', () {
      expect(ClockGuard.check(DateTime(2020, 1, 1), null), isNull);
    });

    test('device time after the last event is normal', () {
      final warning = ClockGuard.check(
        recorded.add(const Duration(hours: 3)),
        recorded,
      );
      expect(warning, isNull);
    });

    test('device time equal to the last event is normal', () {
      expect(ClockGuard.check(recorded, recorded), isNull);
    });

    test('a small gap inside tolerance is ignored', () {
      final warning = ClockGuard.check(
        recorded.subtract(const Duration(minutes: 2)),
        recorded,
      );
      expect(warning, isNull);
    });

    test('moving back further than tolerance warns', () {
      final warning = ClockGuard.check(
        recorded.subtract(const Duration(hours: 2)),
        recorded,
      );

      expect(warning, isNotNull);
      expect(warning!.latestRecorded, recorded);
      expect(warning.drift, const Duration(hours: 2));
    });

    test('the summary reads in the biggest sensible unit', () {
      ClockWarning warn(Duration back) => ClockGuard.check(
            recorded.subtract(back),
            recorded,
          )!;

      expect(warn(const Duration(minutes: 30)).summary, '30 minutes');
      expect(warn(const Duration(hours: 1)).summary, '1 hour');
      expect(warn(const Duration(hours: 5)).summary, '5 hours');
      expect(warn(const Duration(days: 1)).summary, '1 day');
      expect(warn(const Duration(days: 400)).summary, '400 days');
    });

    test('a clock reset to years earlier is caught', () {
      final warning = ClockGuard.check(DateTime(2020, 1, 1), recorded);

      expect(warning, isNotNull);
      expect(warning!.driftDays, greaterThan(2000));
    });
  });
}
