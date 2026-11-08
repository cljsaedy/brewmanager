import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// where the api keys live (rule 11): android's secure storage, encrypted, outside the sqlite file
// so a database backup never carries them, and they are never in code, the repo or tests

// the 3 keys, the names are what secure storage saves them under
enum ApiKey {
  mailjetKey('mailjet_api_key'),
  mailjetSecret('mailjet_secret_key'),
  groqKey('groq_api_key');

  const ApiKey(this.storageName);

  final String storageName;
}

// read, save and remove a key
// abstract so tests can use MemoryKeyStore, a widget test has no android secure storage
abstract class KeyStore {
  Future<String?> read(ApiKey key);
  Future<void> write(ApiKey key, String value);
  Future<void> delete(ApiKey key);
}

// the real one, used on the tablet
// AndroidOptions() = the default: the key is encrypted with AES-GCM, and that key is locked by android's keystore
class SecureKeyStore implements KeyStore {
  SecureKeyStore()
    : _storage = const FlutterSecureStorage(aOptions: AndroidOptions());

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(ApiKey key) => _storage.read(key: key.storageName);

  @override
  Future<void> write(ApiKey key, String value) =>
      _storage.write(key: key.storageName, value: value);

  @override
  Future<void> delete(ApiKey key) => _storage.delete(key: key.storageName);
}

// keeps keys in memory only, for tests, nothing is saved anywhere
class MemoryKeyStore implements KeyStore {
  final Map<ApiKey, String> values = {};

  @override
  Future<String?> read(ApiKey key) async => values[key];

  @override
  Future<void> write(ApiKey key, String value) async => values[key] = value;

  @override
  Future<void> delete(ApiKey key) async => values.remove(key);
}
