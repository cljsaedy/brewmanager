import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

// makes salts, hashes pins/recovery codes, and makes new recovery codes
// nothing here touches the database, so it is easy to test
class PinHasher {
  // private constructor, just call PinHasher.hash(...) etc
  PinHasher._();

  // owner pin is always 4 digits
  static const int pinLength = 4;

  // letters/numbers used in recovery codes, no 0 O 1 I L since they look alike when written down
  static const String _codeLetters = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  // Random.secure = random numbers safe for security stuff (normal Random is guessable)
  static final Random _random = Random.secure();

  // new random salt, 16 random bytes turned into text
  // salt is mixed into the hash so the same pin gives a different hash on every tablet
  static String newSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  // sha-256 of salt + secret, as a 64 character hex text
  // one way only, you cant get the pin back from the hash
  static String hash(String secret, String salt) {
    final bytes = utf8.encode(salt + secret);
    return sha256.convert(bytes).toString();
  }

  // true when the pin is exactly 4 digits
  static bool isValidPin(String pin) {
    return RegExp(r'^[0-9]{4}$').hasMatch(pin);
  }

  // new recovery code like 7KQ2-M9XA (8 random characters with a dash in the middle)
  static String newRecoveryCode() {
    final chars = List.generate(
      8,
      (_) => _codeLetters[_random.nextInt(_codeLetters.length)],
    ).join();
    return '${chars.substring(0, 4)}-${chars.substring(4)}';
  }

  // makes uppercase and removes the dash and spaces, so "7kq2 m9xa" matches "7KQ2-M9XA"
  // always run this before hashing a recovery code
  static String normalizeRecoveryCode(String code) {
    return code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }
}
