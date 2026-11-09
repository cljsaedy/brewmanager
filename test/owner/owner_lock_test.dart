import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/owner/owner_lock.dart';

void main() {
  test('the lock waits only while a file screen is open', () async {
    expect(OwnerLock.isPaused, isFalse);

    final seen = await OwnerLock.pauseWhile(() async => OwnerLock.isPaused);

    expect(seen, isTrue);
    expect(OwnerLock.isPaused, isFalse);
  });

  test('the lock is back on even when the file screen fails', () async {
    await expectLater(
      OwnerLock.pauseWhile<void>(() async => throw StateError('picker')),
      throwsStateError,
    );

    expect(OwnerLock.isPaused, isFalse);
  });
}
