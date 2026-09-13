import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../security/pin_hasher.dart';
import 'database_helper.dart';

/// All database access for the `users` table lives here, so no screen ever
/// writes SQL or touches a PIN hash directly.
class UserRepository {
  UserRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// The PIN the seeded Manager account starts with. The app refuses to do
  /// anything until this has been changed (see [isDefaultManagerPinInUse]).
  static const String defaultManagerPin = '0000';

  /// Returns the active user whose PIN matches, or null if none does.
  ///
  /// Hashes are salted, so we cannot look the PIN up directly. Instead we
  /// load every active user and verify against each stored hash. A cafe has
  /// a handful of staff, so this is cheap.
  Future<AppUser?> findByPin(String pin) async {
    final db = await _helper.database;
    final rows = await db.query('users', where: 'is_active = 1');

    for (final row in rows) {
      final stored = row['pin_hash'] as String;
      if (PinHasher.verify(pin, stored)) {
        return AppUser.fromMap(row);
      }
    }
    return null;
  }

  /// Replaces the stored hash for [userId] with a fresh salted hash of [newPin].
  Future<void> updatePin(int userId, String newPin) async {
    final db = await _helper.database;
    await db.update(
      'users',
      {'pin_hash': PinHasher.hash(newPin)},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// Returns an active Manager who still has the seeded default PIN, or null
  /// if the default has been changed.
  ///
  /// This is how "force PIN change on first launch" is detected without a
  /// separate settings flag: once the PIN is changed, this check naturally
  /// stops matching.
  Future<AppUser?> findManagerWithDefaultPin() async {
    final db = await _helper.database;
    final rows = await db.query(
      'users',
      where: 'role = ? AND is_active = 1',
      whereArgs: [UserRole.manager.dbValue],
    );

    for (final row in rows) {
      if (PinHasher.verify(defaultManagerPin, row['pin_hash'] as String)) {
        return AppUser.fromMap(row);
      }
    }
    return null;
  }

  /// Inserts the default Manager account. Called once from
  /// [DatabaseHelper] when the database file is first created. Takes the
  /// transaction it must run inside rather than opening its own connection.
  static Future<void> seedDefaultManager(DatabaseExecutor txn) async {
    await txn.insert('users', {
      'name': 'Manager',
      'role': UserRole.manager.dbValue,
      'pin_hash': PinHasher.hash(defaultManagerPin),
      'is_active': 1,
    });
  }
}
