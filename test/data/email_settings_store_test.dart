import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/email_settings_store.dart';
import 'package:brewmanager/security/key_store.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late MemoryKeyStore keys;
  late EmailSettingsStore store;

  setUp(() async {
    db = await openTestDatabase();
    keys = MemoryKeyStore();
    store = EmailSettingsStore(db, keys);
  });

  tearDown(() async {
    await db.close();
  });

  test('nothing is set at first', () async {
    final settings = await store.load();

    expect(settings.ownerEmail, isNull);
    expect(settings.senderEmail, isNull);
    expect(settings.savedKeys, isEmpty);
  });

  test('emails are trimmed and saved in app_settings', () async {
    await store.saveEmails(
      ownerEmail: '  owner@example.com ',
      senderEmail: 'reports@example.com',
    );

    final settings = await store.load();
    expect(settings.ownerEmail, 'owner@example.com');
    expect(settings.senderEmail, 'reports@example.com');
  });

  test('an empty box removes the email', () async {
    await store.saveEmails(
      ownerEmail: 'owner@example.com',
      senderEmail: 'reports@example.com',
    );
    await store.saveEmails(ownerEmail: '', senderEmail: 'reports@example.com');

    expect((await store.load()).ownerEmail, isNull);
  });

  test('a wrong email saves neither', () async {
    expect(
      () => store.saveEmails(
        ownerEmail: 'owner@example.com',
        senderEmail: 'not an email',
      ),
      throwsArgumentError,
    );

    expect((await store.load()).ownerEmail, isNull);
  });

  test('keys are trimmed and only say they are saved', () async {
    await store.saveKey(ApiKey.groqKey, '  test-groq-value\n');

    final settings = await store.load();
    expect(settings.hasKey(ApiKey.groqKey), isTrue);
    expect(settings.hasKey(ApiKey.mailjetKey), isFalse);
    expect(await store.key(ApiKey.groqKey), 'test-groq-value');
  });

  test('keys never go in the database (rule 11)', () async {
    await store.saveEmails(
      ownerEmail: 'owner@example.com',
      senderEmail: 'reports@example.com',
    );
    for (final key in ApiKey.values) {
      await store.saveKey(key, 'test-secret-${key.name}');
    }

    final rows = await db.query('app_settings');
    for (final row in rows) {
      expect(row['value'].toString(), isNot(contains('test-secret')));
    }
  });

  test('a removed key is gone', () async {
    await store.saveKey(ApiKey.mailjetSecret, 'test-value');
    await store.removeKey(ApiKey.mailjetSecret);

    expect((await store.load()).hasKey(ApiKey.mailjetSecret), isFalse);
  });

  test('an empty key is refused', () async {
    expect(() => store.saveKey(ApiKey.groqKey, '   '), throwsArgumentError);
  });

  test('the email check', () {
    expect(looksLikeEmail('owner@example.com'), isTrue);
    expect(looksLikeEmail('owner@example'), isFalse);
    expect(looksLikeEmail('owner example.com'), isFalse);
    expect(looksLikeEmail('a b@example.com'), isFalse);
  });
}
