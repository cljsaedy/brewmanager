import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../security/pin_hasher.dart';
import 'database_helper.dart';

/// all db access for the users table, so screens never write sql or touch a pin hash
class UserRepository {
  UserRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// pin the seeded manager starts with, app won't do anything until it's changed
  static const String defaultManagerPin = '0000';

  /// returns the active user whose pin matches, null if none
  Future<AppUser?> findByPin(String pin) async {
    final db = await _helper.database;
    final rows = await db.query('users', where: 'is_active = 1');

    // hashes are salted so we can't look the pin up directly, just check each user (cafe only has a few)
    for (final row in rows) {
      final stored = row['pin_hash'] as String;
      if (PinHasher.verify(pin, stored)) {
        return AppUser.fromMap(row);
      }
    }
    return null;
  }

  /// replaces the stored hash with a fresh salted hash of the new pin
  Future<void> updatePin(int userId, String newPin) async {
    final db = await _helper.database;
    await db.update(
      'users',
      {'pin_hash': PinHasher.hash(newPin)},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// returns an active manager still on the default pin, null once it's been changed
  Future<AppUser?> findManagerWithDefaultPin() async {
    final db = await _helper.database;
    final rows = await db.query(
      'users',
      where: 'role = ? AND is_active = 1',
      whereArgs: [UserRole.manager.dbValue],
    );

    // this is the "force pin change on first launch" check, no settings flag needed since once the pin changes this stops matching
    for (final row in rows) {
      if (PinHasher.verify(defaultManagerPin, row['pin_hash'] as String)) {
        return AppUser.fromMap(row);
      }
    }
    return null;
  }

  /// inserts the default manager, called once from DatabaseHelper when the db is first created
  static Future<void> seedDefaultManager(DatabaseExecutor txn) async {
    // takes the transaction it must run in instead of opening its own connection
    await txn.insert('users', {
      'name': 'Manager',
      'role': UserRole.manager.dbValue,
      'pin_hash': PinHasher.hash(defaultManagerPin),
      'is_active': 1,
    });
  }
}
