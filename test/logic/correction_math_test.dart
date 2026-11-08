import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/correction_math.dart';
import 'package:brewmanager/logic/count_math.dart';

void main() {
  const restock2 = DayEvent(isRestock: true, qty: 4000);
  const finished = DayEvent(isRestock: false, qty: 1);

  ReplayResult replay(ContainerState start, List<DayEvent> events) {
    return replayDay(start: start, events: events, containerSize: 2000);
  }

  group('replayDay', () {
    test('no events keeps the corrected values', () {
      const start = ContainerState(sealed: 3, level: level50, exactQty: null);

      final result = replay(start, const []);

      expect(result.end, start);
      expect(result.beforeEachFinish, isEmpty);
    });

    test('a restock adds whole containers to sealed', () {
      final result = replay(
        const ContainerState(sealed: 1, level: level25, exactQty: null),
        const [restock2],
      );

      expect(
        result.end,
        const ContainerState(sealed: 3, level: level25, exactQty: null),
      );
    });

    test('a finished tap opens a sealed one', () {
      final result = replay(
        const ContainerState(sealed: 2, level: level25, exactQty: null),
        const [finished],
      );

      expect(
        result.end,
        const ContainerState(sealed: 1, level: levelFull, exactQty: null),
      );
      expect(result.beforeEachFinish, [
        const ContainerState(sealed: 2, level: level25, exactQty: null),
      ]);
    });

    test('a finished tap with nothing sealed leaves none open', () {
      final result = replay(
        const ContainerState(sealed: 0, level: levelNone, exactQty: 640),
        const [finished],
      );

      expect(
        result.end,
        const ContainerState(sealed: 0, level: levelNone, exactQty: null),
      );
    });

    test('events go in order, each finish remembers what was before', () {
      // corrected End: 0 sealed + 50%, then a finish, a restock of 2, another finish
      final result = replay(
        const ContainerState(sealed: 0, level: level50, exactQty: null),
        const [finished, restock2, finished],
      );

      expect(
        result.end,
        const ContainerState(sealed: 1, level: levelFull, exactQty: null),
      );
      expect(result.beforeEachFinish, [
        const ContainerState(sealed: 0, level: level50, exactQty: null),
        const ContainerState(sealed: 2, level: levelNone, exactQty: null),
      ]);
    });
  });

  group('replayNumber', () {
    test('the corrected End plus every restock', () {
      expect(
        replayNumber(
          start: 6,
          events: const [
            DayEvent(isRestock: true, qty: 10),
            DayEvent(isRestock: true, qty: 2.5),
          ],
        ),
        18.5,
      );
    });

    test('no events is the corrected End', () {
      expect(replayNumber(start: 6, events: const []), 6);
    });
  });
}
