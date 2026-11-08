import 'package:sqflite/sqflite.dart';

import '../security/pin_hasher.dart';
import 'email_settings_store.dart';

// saves and checks the owner pin and recovery code in the app_settings table
// only hashes + salts are saved, never the plain pin or code
class OwnerPinStore {
  OwnerPinStore(this._db);

  final Database _db;

  // the db this store uses, the pin screens pass it on to the owner section after unlocking
  Database get db => _db;

  // key names of the rows in app_settings
  static const String pinHashKey = 'pin_hash';
  static const String pinSaltKey = 'pin_salt';
  static const String recoveryHashKey = 'recovery_hash';
  static const String recoverySaltKey = 'recovery_salt';

  // true once a pin was set up
  Future<bool> hasPin() async {
    return await _read(pinHashKey) != null;
  }

  // saves a new pin and makes a new recovery code, gives back the plain code so the screen can show it once
  // making a new code every time means an old code stops working after it was used
  Future<String> setPin(String pin) async {
    if (!PinHasher.isValidPin(pin)) {
      throw ArgumentError('PIN must be ${PinHasher.pinLength} digits');
    }

    final pinSalt = PinHasher.newSalt();
    final code = PinHasher.newRecoveryCode();
    final codeSalt = PinHasher.newSalt();

    // one transaction so all 4 rows save together, or none of them if something fails
    // (a pin hash saved without its salt would lock the owner out)
    await _db.transaction((txn) async {
      await _write(txn, pinHashKey, PinHasher.hash(pin, pinSalt));
      await _write(txn, pinSaltKey, pinSalt);
      await _write(
        txn,
        recoveryHashKey,
        PinHasher.hash(PinHasher.normalizeRecoveryCode(code), codeSalt),
      );
      await _write(txn, recoverySaltKey, codeSalt);
      await _queueRecoveryEmail(txn, code);
    });

    return code;
  }

  // makes a new recovery code without changing the pin, from owner settings
  // the old code stops working, the new one is emailed if an owner email is set
  // gives back the plain code so the screen can show it once
  Future<String> newRecoveryCode() async {
    final code = PinHasher.newRecoveryCode();
    final codeSalt = PinHasher.newSalt();
    await _db.transaction((txn) async {
      await _write(
        txn,
        recoveryHashKey,
        PinHasher.hash(PinHasher.normalizeRecoveryCode(code), codeSalt),
      );
      await _write(txn, recoverySaltKey, codeSalt);
      await _queueRecoveryEmail(txn, code);
    });
    return code;
  }

  // the setup wizard sets the pin before the owner email exists, so the code couldnt be emailed then
  // it keeps the plain code in memory and calls this once the owner email is saved
  // nothing happens if there is still no owner email (the owner skipped it)
  Future<void> emailRecoveryCode(String code) {
    return _db.transaction((txn) => _queueRecoveryEmail(txn, code));
  }

  // emails the new code to the owner too, only if an owner email is set (rule 11)
  // an older recovery email that wasnt sent yet is removed first, its code just stopped working
  // the body gets blanked after it is sent (see OutboxSender) so the plain code doesnt stay in the db
  Future<void> _queueRecoveryEmail(Transaction txn, String code) async {
    final rows = await txn.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [EmailSettingsStore.ownerEmailKey],
    );
    if (rows.isEmpty) return;

    await txn.delete('outbox', where: "kind = 'recovery' AND status != 'sent'");
    await txn.insert('outbox', {
      'kind': 'recovery',
      'subject': 'BrewManager PIN recovery code',
      'html_body':
          '<p>Your new owner PIN recovery code is:</p>'
          '<h2>$code</h2>'
          '<p>Use it on the "Forgot PIN?" screen if you forget your PIN. '
          'Each time the PIN is set, a new code replaces this one.</p>',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // true when the typed pin matches the saved one
  Future<bool> checkPin(String pin) async {
    return _matches(pin, hashKey: pinHashKey, saltKey: pinSaltKey);
  }

  // true when the typed recovery code matches the saved one (case, dash and spaces dont matter)
  Future<bool> checkRecoveryCode(String code) async {
    return _matches(
      PinHasher.normalizeRecoveryCode(code),
      hashKey: recoveryHashKey,
      saltKey: recoverySaltKey,
    );
  }

  // hashes the typed value with the saved salt and compares it with the saved hash
  Future<bool> _matches(
    String typed, {
    required String hashKey,
    required String saltKey,
  }) async {
    final savedHash = await _read(hashKey);
    final salt = await _read(saltKey);
    if (savedHash == null || salt == null) return false;
    return PinHasher.hash(typed, salt) == savedHash;
  }

  // gets one value from app_settings, null if the key isnt there
  Future<String?> _read(String key) async {
    final rows = await _db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  // saves one value, replaces the old row if the key already exists
  // DatabaseExecutor = works with both the normal db and a transaction
  static Future<void> _write(
    DatabaseExecutor db,
    String key,
    String value,
  ) async {
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
