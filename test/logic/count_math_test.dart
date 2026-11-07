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

  group('restock math', () {
    test('containersIn gives whole containers', () {
      expect(containersIn(4000, 2000), 2);
      // a size with decimals doesnt divide back perfectly
      expect(containersIn(99.9, 33.3), 3);
    });

    test('sealedAfterRemove stops at 0', () {
      expect(sealedAfterRemove(3, 2), 1);
      expect(sealedAfterRemove(1, 2), 0);
    });
  });

  group('container finished', () {
    test('with sealed left, the next one gets opened full', () {
      expect(sealedAfterFinish(2), 1);
      expect(levelAfterFinish(2), levelFull);
    });

    test('the last sealed one still gets opened', () {
      expect(sealedAfterFinish(1), 0);
      expect(levelAfterFinish(1), levelFull);
    });

    test('with no sealed left, nothing stays open', () {
      expect(sealedAfterFinish(0), 0);
      expect(levelAfterFinish(0), levelNone);
    });
  });

  group('can finish', () {
    test('nothing sealed, nothing open and no typed amount = no', () {
      expect(
        canFinishContainer(sealed: 0, level: levelNone, exactQty: null),
        isFalse,
      );
    });

    test('a sealed one, an open level or a typed amount = yes', () {
      expect(
        canFinishContainer(sealed: 1, level: levelNone, exactQty: null),
        isTrue,
      );
      expect(
        canFinishContainer(sealed: 0, level: level25, exactQty: null),
        isTrue,
      );
      expect(
        canFinishContainer(sealed: 0, level: levelNone, exactQty: 350),
        isTrue,
      );
    });
  });

  group('undo of a finished tap', () {
    test('sealed only goes up if the tap took one out', () {
      expect(sealedAfterUndo(sealed: 1, sealedBefore: 2), 2);
      expect(sealedAfterUndo(sealed: 1, sealedBefore: 0), 1);
    });

    test('sealed builds on the number from now, not from before', () {
      // tap took 1 of 1, then 3 arrived
      expect(sealedAfterUndo(sealed: 3, sealedBefore: 1), 4);
    });

    test('opened still full after a tap that opened one', () {
      expect(
        openedStillFromFinish(
          level: levelFull,
          exactQty: null,
          sealedBefore: 1,
        ),
        isTrue,
      );
    });

    test('opened still none after a tap with no sealed', () {
      expect(
        openedStillFromFinish(
          level: levelNone,
          exactQty: null,
          sealedBefore: 0,
        ),
        isTrue,
      );
    });

    test('a changed level or a typed amount means it was edited', () {
      expect(
        openedStillFromFinish(level: level50, exactQty: null, sealedBefore: 1),
        isFalse,
      );
      expect(
        openedStillFromFinish(level: levelFull, exactQty: 300, sealedBefore: 1),
        isFalse,
      );
    });
  });

  group('amountUsed', () {
    test('start plus in minus end', () {
      expect(amountUsed(start: 8, inQty: 0, end: 6), 2);
      expect(amountUsed(start: 8, inQty: 5, end: 6), 7);
    });

    test('nothing moved is 0', () {
      expect(amountUsed(start: 8, inQty: 0, end: 8), 0);
    });

    test('counting more than was there goes below 0', () {
      expect(amountUsed(start: 8, inQty: 0, end: 10), -2);
    });

    test('no tiny decimal leftovers', () {
      // 0.3 - 0.1 is 0.19999999999999998 on a computer
      expect(amountUsed(start: 0.3, inQty: 0, end: 0.1), 0.2);
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
