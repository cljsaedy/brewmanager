import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/security/pin_hasher.dart';

void main() {
  group('hash', () {
    test('same pin and same salt give the same hash', () {
      final salt = PinHasher.newSalt();
      expect(PinHasher.hash('1234', salt), PinHasher.hash('1234', salt));
    });

    test('same pin with a different salt gives a different hash', () {
      expect(
        PinHasher.hash('1234', PinHasher.newSalt()),
        isNot(PinHasher.hash('1234', PinHasher.newSalt())),
      );
    });

    test('wrong pin gives a different hash', () {
      final salt = PinHasher.newSalt();
      expect(PinHasher.hash('1234', salt), isNot(PinHasher.hash('1235', salt)));
    });

    test('hash is 64 hex characters and does not contain the pin', () {
      final hash = PinHasher.hash('1234', PinHasher.newSalt());
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(hash.contains('1234'), isFalse);
    });

    test('salts are random', () {
      expect(PinHasher.newSalt(), isNot(PinHasher.newSalt()));
    });
  });

  group('pin rules', () {
    test('only exactly 4 digits is a valid pin', () {
      expect(PinHasher.isValidPin('1234'), isTrue);
      expect(PinHasher.isValidPin('0000'), isTrue);
      expect(PinHasher.isValidPin('123'), isFalse);
      expect(PinHasher.isValidPin('12345'), isFalse);
      expect(PinHasher.isValidPin('12a4'), isFalse);
      expect(PinHasher.isValidPin(''), isFalse);
    });
  });

  group('recovery code', () {
    test('looks like XXXX-XXXX with no look-alike characters', () {
      for (int i = 0; i < 50; i++) {
        final code = PinHasher.newRecoveryCode();
        expect(code, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
        expect(code, isNot(matches(RegExp('[01OIL]'))));
      }
    });

    test('codes are random', () {
      expect(PinHasher.newRecoveryCode(), isNot(PinHasher.newRecoveryCode()));
    });

    test('lowercase, spaces and missing dash still match', () {
      expect(PinHasher.normalizeRecoveryCode('7kq2-m9xa'), '7KQ2M9XA');
      expect(PinHasher.normalizeRecoveryCode(' 7KQ2 M9XA '), '7KQ2M9XA');
      expect(PinHasher.normalizeRecoveryCode('7KQ2M9XA'), '7KQ2M9XA');
    });
  });
}
