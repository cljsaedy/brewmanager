import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/count_math.dart';

void main() {
  group('containerEnd', () {
    double end(int sealed, double level, {double? exact}) {
      return containerEnd(
        sealed: sealed,
        containerSize: 2000,
        level: level,
        exactQty: exact,
      );
    }

    test('sealed plus the level part', () {
      expect(end(2, level50), 5000);
      expect(end(0, level25), 500);
      expect(end(1, levelFull), 4000);
    });

    test('only sealed containers', () {
      expect(end(3, levelNone), 6000);
    });

    test('nothing at all is 0', () {
      expect(end(0, levelNone), 0);
    });

    test('an exact amount replaces the level', () {
      expect(end(1, level75, exact: 350), 2350);
    });

    test('an exact amount of 0 still replaces the level', () {
      expect(end(1, level75, exact: 0), 2000);
    });

    test('no tiny decimal leftovers', () {
      // 0.1 * 3 is 0.30000000000000004 on a computer
      expect(
        containerEnd(
          sealed: 0,
          containerSize: 3,
          level: levelAlmostEmpty,
          exactQty: null,
        ),
        0.3,
      );
    });
  });

  group('containerIsExact', () {
    test('no container open is exact', () {
      expect(containerIsExact(level: levelNone, exactQty: null), isTrue);
    });

    test('a typed amount is exact, even with a level saved', () {
      expect(containerIsExact(level: level50, exactQty: 350), isTrue);
    });

    test('any level button is estimated', () {
      for (final level in [
        levelAlmostEmpty,
        level25,
        level50,
        level75,
        levelFull,
      ]) {
        expect(containerIsExact(level: level, exactQty: null), isFalse);
      }
    });
  });
}
