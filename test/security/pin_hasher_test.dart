import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/security/pin_hasher.dart';

void main() {
  group('PinHasher', () {
    test('verifies the PIN it was created from', () {
      final stored = PinHasher.hash('1234');
      expect(PinHasher.verify('1234', stored), isTrue);
    });

    test('rejects a different PIN', () {
      final stored = PinHasher.hash('1234');
      expect(PinHasher.verify('1235', stored), isFalse);
    });

    test('does not store the PIN in plain text', () {
      final stored = PinHasher.hash('1234');
      expect(stored, isNot(contains('1234')));
    });

    test('hashing the same PIN twice gives different stored values (salt)',
        () {
      final first = PinHasher.hash('1234');
      final second = PinHasher.hash('1234');
      expect(first, isNot(equals(second)));
      // but both still verify
      expect(PinHasher.verify('1234', first), isTrue);
      expect(PinHasher.verify('1234', second), isTrue);
    });

    test('rejects a malformed stored value instead of crashing', () {
      expect(PinHasher.verify('1234', 'garbage'), isFalse);
      expect(PinHasher.verify('1234', ''), isFalse);
    });
  });
}
