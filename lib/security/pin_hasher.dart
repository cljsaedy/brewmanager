import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// hashes and checks pins, pure dart so it's unit tested on its own
class PinHasher {
  PinHasher._();

  // stored value looks like salt$hash, salt is random per user and hash is sha256 of salt+pin
  // salt means same pin gives different hashes so one precomputed table can't crack every user
  static const String _separator = r'$';
  static const int _saltBytes = 16;

  /// returns the value to store in users.pin_hash, never the pin itself
  static String hash(String pin) {
    final salt = _generateSalt();
    return '$salt$_separator${_digest(salt, pin)}';
  }

  /// checks if pin matches a value made by hash()
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

  // Random.secure() uses the os crypto source, plain Random() is predictable
  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(_saltBytes, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }
}
