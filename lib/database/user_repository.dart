import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../security/pin_hasher.dart';
import 'database_helper.dart';

/// thrown when a pin is already in use by someone else
///
/// pins are how the app identifies people, so two staff sharing one would mean
/// sales and shifts getting recorded against whichever row was found first
class DuplicatePinException implements Exception {}

/// thrown when deactivating would leave nobody who can manage the system
class LastManagerException implements Exception {}

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

  /// everyone, active first then by name, for the staff screen
  Future<List<AppUser>> getAll() async {
    final db = await _helper.database;
    final rows = await db.query(
      'users',
      orderBy: 'is_active DESC, name COLLATE NOCASE',
    );
    return rows.map(AppUser.fromMap).toList();
  }

  /// replaces the stored hash with a fresh salted hash of the new pin
  Future<void> updatePin(int userId, String newPin) async {
    await _ensurePinIsFree(newPin, exceptUserId: userId);

    final db = await _helper.database;
    await db.update(
      'users',
      {'pin_hash': PinHasher.hash(newPin)},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// adds a staff member, returns the new user_id
  Future<int> createUser({
    required String name,
    required UserRole role,
    required String pin,
  }) async {
    await _ensurePinIsFree(pin);

    final db = await _helper.database;
    return db.insert('users', {
      'name': name.trim(),
      'role': role.dbValue,
      'pin_hash': PinHasher.hash(pin),
      'is_active': 1,
    });
  }

  /// changes a name or role, the pin is changed separately
  Future<void> updateUser({
    required int userId,
    required String name,
    required UserRole role,
  }) async {
    // demoting the only manager would leave nobody able to void or change settings
    if (role != UserRole.manager) {
      await _ensureNotLastActiveManager(userId);
    }

    final db = await _helper.database;
    await db.update(
      'users',
      {'name': name.trim(), 'role': role.dbValue},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// deactivates or reactivates someone
  ///
  /// staff are deactivated rather than deleted, same reasoning as archiving an
  /// ingredient, past shifts and voids point at the user who did them
  Future<void> setActive(int userId, bool isActive) async {
    if (!isActive) {
      await _ensureNotLastActiveManager(userId);
    }

    final db = await _helper.database;
    await db.update(
      'users',
      {'is_active': isActive ? 1 : 0},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  /// pins are how the app knows who someone is, so no two active users share one
  Future<void> _ensurePinIsFree(String pin, {int? exceptUserId}) async {
    final existing = await findByPin(pin);
    if (existing == null) return;
    if (existing.userId == exceptUserId) return;
    throw DuplicatePinException();
  }

  /// stops the app being left with nobody who can manage it
  Future<void> _ensureNotLastActiveManager(int userId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'users',
      columns: ['user_id'],
      where: 'role = ? AND is_active = 1 AND user_id != ?',
      whereArgs: [UserRole.manager.dbValue, userId],
    );
    if (rows.isEmpty) throw LastManagerException();
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
