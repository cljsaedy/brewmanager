import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/business_day.dart';

void main() {
  group('addDays', () {
    test('goes over the end of a month and year', () {
      expect(addDays('2026-10-31', 1), '2026-11-01');
      expect(addDays('2026-12-31', 1), '2027-01-01');
    });

    test('knows a leap day', () {
      expect(addDays('2028-02-28', 1), '2028-02-29');
    });
  });

  group('daysBetween', () {
    test('counts forward and back', () {
      expect(daysBetween('2026-10-28', '2026-11-02'), 5);
      expect(daysBetween('2026-11-02', '2026-10-28'), -5);
      expect(daysBetween('2026-11-02', '2026-11-02'), 0);
    });
  });

  group('canSubmitOn', () {
    test('the same date or later is fine', () {
      expect(
        canSubmitOn(draftDate: '2026-10-30', chosenDate: '2026-10-30'),
        isTrue,
      );
      expect(
        canSubmitOn(draftDate: '2026-10-30', chosenDate: '2026-10-31'),
        isTrue,
      );
    });

    test('an earlier date is refused', () {
      expect(
        canSubmitOn(draftDate: '2026-10-30', chosenDate: '2026-10-29'),
        isFalse,
      );
    });
  });

  group('skippedDayWarning', () {
    test('today or 1 day behind has no warning', () {
      expect(
        skippedDayWarning(draftDate: '2026-10-30', today: '2026-10-30'),
        isNull,
      );
      expect(
        skippedDayWarning(draftDate: '2026-10-29', today: '2026-10-30'),
        isNull,
      );
    });

    test('2 days behind warns', () {
      expect(
        skippedDayWarning(draftDate: '2026-10-28', today: '2026-10-30'),
        'This is 2 days ago. Did you skip a day?',
      );
    });

    test('a draft ahead of the tablet has no warning', () {
      expect(
        skippedDayWarning(draftDate: '2026-10-31', today: '2026-10-30'),
        isNull,
      );
    });
  });

  group('skippedDates', () {
    test('nothing skipped on the same date', () {
      expect(
        skippedDates(draftDate: '2026-10-30', chosenDate: '2026-10-30'),
        isEmpty,
      );
    });

    test('has the draft date, not the chosen one', () {
      expect(skippedDates(draftDate: '2026-10-28', chosenDate: '2026-10-30'), [
        '2026-10-28',
        '2026-10-29',
      ]);
    });

    test('goes over the end of a month', () {
      expect(skippedDates(draftDate: '2026-10-31', chosenDate: '2026-11-02'), [
        '2026-10-31',
        '2026-11-01',
      ]);
    });
  });
}
