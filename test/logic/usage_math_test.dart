import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/logic/usage_math.dart';

void main() {
  group('expectedUsage', () {
    test('tally quantity x recipe amount, added up', () {
      expect(
        expectedUsage(const [
          RecipeUse(menuQty: 3, amount: 30),
          RecipeUse(menuQty: 2, amount: 45),
        ]),
        180,
      );
    });

    test('nothing tallied is 0', () {
      expect(expectedUsage(const []), 0);
    });

    test('no tiny decimal leftovers', () {
      // 3 * 2.96 is 8.879999999999999 on a computer
      expect(expectedUsage(const [RecipeUse(menuQty: 3, amount: 2.96)]), 8.88);
    });
  });

  group('actualIsExact', () {
    test('both ends exact = exact', () {
      expect(actualIsExact(startIsExact: true, endIsExact: true), isTrue);
    });

    test('one estimated end = estimated', () {
      expect(actualIsExact(startIsExact: false, endIsExact: true), isFalse);
      expect(actualIsExact(startIsExact: true, endIsExact: false), isFalse);
    });
  });

  group('gapOf', () {
    test('more used than the tally explains is positive', () {
      expect(gapOf(actual: 500, expected: 420, isExact: true), 80);
    });

    test('less used is negative', () {
      expect(gapOf(actual: 400, expected: 420, isExact: true), -20);
    });

    test('used just what was expected is 0, not empty', () {
      expect(gapOf(actual: 420, expected: 420, isExact: true), 0);
    });

    test('estimated, no expected or no actual gives no gap', () {
      expect(gapOf(actual: 500, expected: 420, isExact: false), isNull);
      expect(gapOf(actual: 500, expected: null, isExact: true), isNull);
      expect(gapOf(actual: null, expected: 420, isExact: true), isNull);
    });
  });

  group('dayUsage', () {
    // a fries-like number item, low at 5 pcs, change only what the test cares about
    DayUsage usage({
      double start = 8,
      bool startIsExact = true,
      double inQty = 0,
      double end = 6,
      bool endIsExact = true,
      bool isOpening = false,
      bool inRecipe = true,
      List<RecipeUse> uses = const [RecipeUse(menuQty: 2, amount: 1)],
    }) {
      return dayUsage(
        start: start,
        startIsExact: startIsExact,
        inQty: inQty,
        end: end,
        endIsExact: endIsExact,
        isOpening: isOpening,
        inRecipe: inRecipe,
        uses: uses,
        lowMode: LowMode.exact,
        lowValue: 5,
        containerSize: null,
        countType: CountType.number,
      );
    }

    test('an exact item gets actual, expected and gap', () {
      final result = usage(
        inQty: 5,
        end: 6,
        uses: const [RecipeUse(menuQty: 4, amount: 1)],
      );

      expect(result.actual, 7);
      expect(result.expected, 4);
      expect(result.actualIsExact, isTrue);
      expect(result.gap, 3);
    });

    test('a container item gets no daily gap, exact or not', () {
      final result = dayUsage(
        start: 3000,
        startIsExact: true,
        inQty: 0,
        end: 2500,
        endIsExact: true,
        isOpening: false,
        inRecipe: true,
        uses: const [RecipeUse(menuQty: 2, amount: 100)],
        lowMode: LowMode.containers,
        lowValue: 1,
        containerSize: 2000,
        countType: CountType.container,
      );

      expect(result.actual, 500);
      expect(result.expected, 200);
      expect(result.gap, isNull);
    });

    test('an estimated start or end gives no gap but keeps both numbers', () {
      for (final result in [
        usage(startIsExact: false),
        usage(endIsExact: false),
      ]) {
        expect(result.actual, 2);
        expect(result.expected, 2);
        expect(result.actualIsExact, isFalse);
        expect(result.gap, isNull);
      }
    });

    test('in a recipe with nothing tallied expects 0 and shows the gap', () {
      final result = usage(uses: const []);

      expect(result.expected, 0);
      expect(result.gap, 2);
    });

    test('in no recipe shows actual only', () {
      final result = usage(inRecipe: false, uses: const []);

      expect(result.actual, 2);
      expect(result.expected, isNull);
      expect(result.gap, isNull);
    });

    test('an opening count shows no usage, even with a restock', () {
      final result = usage(start: 0, inQty: 5, end: 20, isOpening: true);

      expect(result.actual, isNull);
      expect(result.expected, isNull);
      expect(result.gap, isNull);
      expect(result.actualIsExact, isFalse);
    });

    test('counting more than was there gives a negative actual', () {
      final result = usage(start: 8, end: 10);

      expect(result.actual, -2);
      expect(result.gap, -4);
    });

    test('the restock flag follows End, opening count too', () {
      expect(usage(end: 5).restockFlag, isTrue);
      expect(usage(end: 6).restockFlag, isFalse);
      expect(usage(end: 3, isOpening: true).restockFlag, isTrue);
    });

    test('a level in containers works for the restock flag', () {
      final result = dayUsage(
        start: 6000,
        startIsExact: false,
        inQty: 0,
        end: 4000,
        endIsExact: false,
        isOpening: false,
        inRecipe: true,
        uses: const [],
        lowMode: LowMode.containers,
        lowValue: 2,
        containerSize: 2000,
        countType: CountType.container,
      );

      expect(result.restockFlag, isTrue);
    });
  });

  group('containerCheck', () {
    PastDay day(
      String date, {
      double? expected = 100,
      int finished = 0,
      bool isOpening = false,
    }) {
      return PastDay(
        date: date,
        expected: expected,
        containersFinished: finished,
        isOpening: isOpening,
      );
    }

    ContainerCheck? check({
      int finished = 1,
      bool isOpening = false,
      double? expectedToday = 200,
      List<PastDay> earlierDays = const [],
    }) {
      return containerCheck(
        today: '2026-11-05',
        containersFinished: finished,
        isOpening: isOpening,
        containerSize: 2000,
        expectedToday: expectedToday,
        earlierDays: earlierDays,
      );
    }

    test('nothing finished gives no check', () {
      expect(check(finished: 0), isNull);
    });

    test('an opening count gives no check, even with one finished', () {
      expect(check(isOpening: true), isNull);
    });

    test('goes back to the first count, without that day', () {
      final result = check(
        earlierDays: [
          day('2026-11-02', expected: null, isOpening: true),
          day('2026-11-03', expected: 300),
          day('2026-11-04', expected: 400),
        ],
      )!;

      expect(result.containers, 1);
      expect(result.containerTotal, 2000);
      // 200 today + 400 + 300
      expect(result.expectedSinceLast, 900);
      expect(result.sinceDate, '2026-11-02');
    });

    test('stops at the last finished container, without that day', () {
      final result = check(
        earlierDays: [
          day('2026-11-01', expected: null, isOpening: true),
          day('2026-11-02', expected: 999),
          day('2026-11-03', expected: 888, finished: 1),
          day('2026-11-04', expected: 400),
        ],
      )!;

      // 200 today + 400, the 3rd was already in its own check
      expect(result.expectedSinceLast, 600);
      expect(result.sinceDate, '2026-11-03');
    });

    test('a restored item starts over at its new opening count', () {
      final result = check(
        earlierDays: [
          day('2026-11-01', expected: 999),
          day('2026-11-04', expected: null, isOpening: true),
        ],
      )!;

      expect(result.expectedSinceLast, 200);
      expect(result.sinceDate, '2026-11-04');
    });

    group('first check after an opening count', () {
      PastDay opening({required double opened, int finished = 0}) {
        return PastDay(
          date: '2026-11-03',
          expected: null,
          containersFinished: finished,
          isOpening: true,
          openedAmount: opened,
        );
      }

      test('an opened bottle at 50% only counts the part that was left', () {
        final result = check(
          earlierDays: [
            opening(opened: 1000),
            day('2026-11-04', expected: 700),
          ],
        )!;

        expect(result.containers, 1);
        // 50% of 2000 ml
        expect(result.containerTotal, 1000);
        // 200 today + 700
        expect(result.expectedSinceLast, 900);
      });

      test('a 2nd bottle that day counts whole', () {
        final result = check(
          finished: 2,
          earlierDays: [opening(opened: 1000)],
        )!;

        // 1000 left in the first + 1 whole bottle
        expect(result.containerTotal, 3000);
      });

      test('a typed exact amount works the same', () {
        final result = check(earlierDays: [opening(opened: 640)])!;

        expect(result.containerTotal, 640);
      });

      test('nothing opened at the opening count counts a whole bottle', () {
        final result = check(earlierDays: [opening(opened: 0)])!;

        expect(result.containerTotal, 2000);
      });

      test('the next check goes back to whole bottles', () {
        final result = check(
          earlierDays: [
            opening(opened: 1000),
            day('2026-11-04', expected: 700, finished: 1),
          ],
        )!;

        expect(result.containerTotal, 2000);
        expect(result.expectedSinceLast, 200);
        expect(result.sinceDate, '2026-11-04');
      });

      test('a restored item uses its new opening count', () {
        final result = check(
          earlierDays: [
            day('2026-11-01', isOpening: true),
            day('2026-11-02', finished: 1),
            opening(opened: 500),
          ],
        )!;

        expect(result.containerTotal, 500);
        expect(result.sinceDate, '2026-11-03');
      });
    });

    test('the days can come in any order', () {
      final result = check(
        earlierDays: [
          day('2026-11-04', expected: 400),
          day('2026-11-02', expected: null, isOpening: true),
          day('2026-11-03', expected: 300),
        ],
      )!;

      expect(result.expectedSinceLast, 900);
      expect(result.sinceDate, '2026-11-02');
    });

    test('2 containers in one day count both', () {
      final result = check(finished: 2)!;

      expect(result.containers, 2);
      expect(result.containerTotal, 4000);
    });

    test('a past day with no expected adds nothing', () {
      final result = check(
        earlierDays: [
          day('2026-11-03', expected: null, isOpening: true),
          day('2026-11-04', expected: null),
        ],
      )!;

      expect(result.expectedSinceLast, 200);
    });

    test('an item in no recipe still reports, with no expected', () {
      final result = check(
        expectedToday: null,
        earlierDays: [day('2026-11-04', expected: null, isOpening: true)],
      )!;

      expect(result.containerTotal, 2000);
      expect(result.expectedSinceLast, isNull);
      expect(result.sinceDate, '2026-11-04');
    });

    test('no earlier days starts from today', () {
      final result = check()!;

      expect(result.expectedSinceLast, 200);
      expect(result.sinceDate, '2026-11-05');
    });

    test('no tiny decimal leftovers', () {
      final result = check(
        expectedToday: 0.1,
        earlierDays: [
          day('2026-11-03', expected: null, isOpening: true),
          day('2026-11-04', expected: 0.2),
        ],
      )!;

      // 0.1 + 0.2 is 0.30000000000000004 on a computer
      expect(result.expectedSinceLast, 0.3);
    });
  });

  test('a scripted day matches the hand math', () {
    // syrup, 2000 ml bottles, typed exact amounts both ends
    // start 2300, restock 2000, end 3500 = 800 used
    // 5 lattes x 30 ml + 4 mochas x 150 ml = 750 expected
    final result = dayUsage(
      start: 2300,
      startIsExact: true,
      inQty: 2000,
      end: 3500,
      endIsExact: true,
      isOpening: false,
      inRecipe: true,
      uses: const [
        RecipeUse(menuQty: 5, amount: 30),
        RecipeUse(menuQty: 4, amount: 150),
      ],
      lowMode: LowMode.containers,
      lowValue: 1,
      containerSize: 2000,
      countType: CountType.container,
    );

    expect(result.actual, 800);
    expect(result.expected, 750);
    // a container item never gets a daily gap, even exact both ends (rule 7)
    // the expected is still saved for the container check
    expect(result.gap, isNull);
    expect(result.restockFlag, isFalse);
  });
}
