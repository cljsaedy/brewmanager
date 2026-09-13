import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hashes and verifies user PINs.
///
/// PINs are never stored. What goes in the database is `salt$hash`, where:
///   - `salt` is a random string generated for that user, and
///   - `hash` is SHA-256 of (salt + pin).
///
/// The salt means two users with the same PIN get different stored values,
/// and an attacker with the database file cannot use one precomputed table
/// of hashes against every user.
///
/// This class is pure Dart with no database access, so it is unit-tested
/// in isolation.
class PinHasher {
  PinHasher._();

  static const String _separator = r'$';
  static const int _saltBytes = 16;

  /// Returns the value to store in `users.pin_hash` for [pin].
  static String hash(String pin) {
    final salt = _generateSalt();
    return '$salt$_separator${_digest(salt, pin)}';
  }

  /// Checks whether [pin] matches a value previously produced by [hash].
  static bool verify(String pin, String stored) {
    final parts = stored.split(_separator);
    if (parts.length != 2) return false;

    final salt = parts[0];
    final expectedHash = parts[1];
    return _digest(salt, pin) == expectedHash;
  }

  static String _digest(String salt, String pin) {
    final bytes = utf8.encode(salt + pin);
    return sha256.convert(bytes).toString();
  }

  /// Random.secure() uses the operating system's cryptographic random
  /// source, unlike plain Random() which is predictable.
  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(_saltBytes, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}
