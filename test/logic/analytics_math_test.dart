import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/analytics_math.dart';

void main() {
  UsagePoint day(String date, double used, double? expected) {
    return UsagePoint(
      date: date,
      used: used,
      expected: expected,
      gap: expected == null ? null : used - expected,
    );
  }

  group('weekStartOf', () {
    test('gives the monday of the week', () {
      // nov 2 2026 is a monday
      expect(weekStartOf('2026-11-02'), '2026-11-02');
      expect(weekStartOf('2026-11-05'), '2026-11-02');
      // sunday still belongs to the week that started monday
      expect(weekStartOf('2026-11-08'), '2026-11-02');
      expect(weekStartOf('2026-11-09'), '2026-11-09');
    });

    test('works across a month', () {
      // sun nov 1 2026 is in the week of mon oct 26
      expect(weekStartOf('2026-11-01'), '2026-10-26');
    });
  });

  group('groupByWeek', () {
    test('adds the days of each week, oldest first', () {
      final weeks = groupByWeek([
        day('2026-11-02', 3, 2),
        day('2026-11-04', 4, 4),
        day('2026-11-09', 5, 6),
      ]);

      expect(weeks, hasLength(2));
      expect(weeks[0].weekStart, '2026-11-02');
      expect(weeks[0].used, 7);
      expect(weeks[0].expected, 6);
      expect(weeks[1].weekStart, '2026-11-09');
      expect(weeks[1].used, 5);
      expect(weeks[1].expected, 6);
    });

    test('a week with no recipe on any day has no expected', () {
      final weeks = groupByWeek([day('2026-11-02', 3, null)]);

      expect(weeks.single.expected, isNull);
    });

    test('a day with no recipe adds only to used', () {
      final weeks = groupByWeek([
        day('2026-11-02', 3, 2),
        day('2026-11-03', 4, null),
      ]);

      expect(weeks.single.used, 7);
      expect(weeks.single.expected, 2);
    });
  });

  group('summarizeGaps', () {
    test('counts days, gap days and the total, biggest total first', () {
      final rows = summarizeGaps({
        // fries: +1, 0, +2 = total 3 on 2 gap days
        1: [
          day('2026-11-02', 3, 2),
          day('2026-11-03', 2, 2),
          day('2026-11-04', 4, 2),
        ],
        // wings: -1 = total -1
        2: [day('2026-11-02', 5, 6)],
        // gloves: no recipe, counted but no gap
        3: [day('2026-11-02', 10, null)],
      });

      expect([for (final row in rows) row.stockItemId], [1, 3, 2]);
      expect(rows[0].daysCounted, 3);
      expect(rows[0].daysWithGap, 2);
      expect(rows[0].totalGap, 3);
      expect(rows[1].daysWithGap, 0);
      expect(rows[1].totalGap, 0);
      expect(rows[2].totalGap, -1);
    });

    test(
      'a + day and a - day cancel in the total but both count as gap days',
      () {
        final rows = summarizeGaps({
          1: [day('2026-11-02', 4, 2), day('2026-11-03', 0, 2)],
        });

        expect(rows.single.totalGap, 0);
        expect(rows.single.daysWithGap, 2);
      },
    );

    test('a tie keeps the item order', () {
      final rows = summarizeGaps({
        5: [day('2026-11-02', 2, 2)],
        4: [day('2026-11-02', 2, 2)],
      });

      expect([for (final row in rows) row.stockItemId], [5, 4]);
    });
  });
}
