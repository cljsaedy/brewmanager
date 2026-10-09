import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/mutex.dart';

void main() {
  group('Mutex', () {
    test('runs jobs one at a time, not interleaved', () async {
      final mutex = Mutex();
      final events = <String>[];

      // each job logs start, yields (where interleaving would happen), then logs end
      Future<void> job(String name) async {
        events.add('$name start');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        events.add('$name end');
      }

      // started together without awaiting the first
      final a = mutex.run(() => job('a'));
      final b = mutex.run(() => job('b'));
      await Future.wait([a, b]);

      // without the mutex this would be a start, b start, a end, b end
      expect(events, ['a start', 'a end', 'b start', 'b end']);
    });

    test('returns each job result to its own caller', () async {
      final mutex = Mutex();

      final a = mutex.run(() async => 1);
      final b = mutex.run(() async => 2);

      expect(await a, 1);
      expect(await b, 2);
    });

    test('a failed job does not block the queue', () async {
      final mutex = Mutex();

      final failed = mutex.run<int>(() async => throw StateError('boom'));
      final after = mutex.run(() async => 'ran anyway');

      await expectLater(failed, throwsStateError);
      expect(await after, 'ran anyway');
    });

    test('is not busy once everything finishes', () async {
      final mutex = Mutex();

      final job = mutex.run(() async =>
          Future<void>.delayed(const Duration(milliseconds: 5)));
      expect(mutex.isBusy, isTrue);

      await job;
      expect(mutex.isBusy, isFalse);
    });
  });
}
