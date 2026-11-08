import 'package:sqflite/sqflite.dart';

import '../security/key_store.dart';

// what the email & ai keys screen shows
// the keys are never shown back, only whether one is saved
class EmailSettings {
  const EmailSettings({
    required this.ownerEmail,
    required this.senderEmail,
    required this.savedKeys,
  });

  // where the daily report goes, null = not set yet
  final String? ownerEmail;
  // the from address, it has to be verified in mailjet or mailjet refuses to send
  final String? senderEmail;
  // which api keys have a value saved
  final Set<ApiKey> savedKeys;

  bool hasKey(ApiKey key) => savedKeys.contains(key);
}

// the owner email and sender email go in app_settings, they are not secret
// the api keys go in the KeyStore (secure storage), never in the db (rule 11)
class EmailSettingsStore {
  EmailSettingsStore(this._db, this._keys);

  final Database _db;
  final KeyStore _keys;

  // key names of the rows in app_settings
  static const String ownerEmailKey = 'owner_email';
  static const String senderEmailKey = 'sender_email';

  Future<EmailSettings> load() async {
    final saved = <ApiKey>{};
    for (final key in ApiKey.values) {
      final value = await _keys.read(key);
      if (value != null && value.isNotEmpty) saved.add(key);
    }
    return EmailSettings(
      ownerEmail: await _read(ownerEmailKey),
      senderEmail: await _read(senderEmailKey),
      savedKeys: saved,
    );
  }

  // the plain key, only for sending (9b and 9c), screens never show it
  Future<String?> key(ApiKey key) => _keys.read(key);

  // saves both emails, trimmed, an empty box removes the email
  // throws ArgumentError if one doesnt look like an email, nothing gets saved then
  Future<void> saveEmails({
    required String ownerEmail,
    required String senderEmail,
  }) async {
    final owner = ownerEmail.trim();
    final sender = senderEmail.trim();
    for (final email in [owner, sender]) {
      if (email.isNotEmpty && !looksLikeEmail(email)) {
        throw ArgumentError('Not an email: $email');
      }
    }

    // both together or neither
    await _db.transaction((txn) async {
      await _write(txn, ownerEmailKey, owner);
      await _write(txn, senderEmailKey, sender);
    });
  }

  // saves a key, trimmed since a copy-paste often brings a space or new line along
  Future<void> saveKey(ApiKey key, String value) async {
    final clean = value.trim();
    if (clean.isEmpty) throw ArgumentError('A key cant be empty');
    await _keys.write(key, clean);
  }

  Future<void> removeKey(ApiKey key) => _keys.delete(key);

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

  // an empty value removes the row, so "not set" is always null
  static Future<void> _write(
    DatabaseExecutor db,
    String key,
    String value,
  ) async {
    if (value.isEmpty) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

// a simple check, something@something.something with no spaces
// it only catches typos, mailjet is the real check
bool looksLikeEmail(String text) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
}
