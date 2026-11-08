import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/email_settings_store.dart';
import 'package:brewmanager/data/owner_pin_store.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late OwnerPinStore store;

  setUp(() async {
    db = await openTestDatabase();
    store = OwnerPinStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // every value saved in app_settings, to check nothing plain was saved
  Future<List<String>> allSavedValues() async {
    final rows = await db.query('app_settings');
    return rows.map((row) => row['value'] as String).toList();
  }

  test('no pin at the start', () async {
    expect(await store.hasPin(), isFalse);
    expect(await store.checkPin('1234'), isFalse);
  });

  test(
    'after setting a pin, the right pin passes and a wrong pin fails',
    () async {
      await store.setPin('1234');

      expect(await store.hasPin(), isTrue);
      expect(await store.checkPin('1234'), isTrue);
      expect(await store.checkPin('4321'), isFalse);
    },
  );

  test('pin and recovery code are never saved as plain text', () async {
    final code = await store.setPin('1234');
    final values = await allSavedValues();

    // 4 rows: pin hash, pin salt, code hash, code salt
    expect(values, hasLength(4));
    for (final value in values) {
      expect(value.contains('1234'), isFalse);
      expect(value.contains(code), isFalse);
      expect(value.contains(code.replaceAll('-', '')), isFalse);
    }
  });

  test('recovery code passes, typed any way, and a wrong code fails', () async {
    final code = await store.setPin('1234');

    expect(await store.checkRecoveryCode(code), isTrue);
    expect(await store.checkRecoveryCode(code.toLowerCase()), isTrue);
    expect(await store.checkRecoveryCode(code.replaceAll('-', '')), isTrue);
    expect(await store.checkRecoveryCode('AAAA-AAAA'), isFalse);
  });

  test(
    'after recovery and a new pin, the old pin and old code stop working',
    () async {
      final oldCode = await store.setPin('1234');

      // forgot pin flow: code checked, then a new pin is made
      expect(await store.checkRecoveryCode(oldCode), isTrue);
      final newCode = await store.setPin('5678');

      expect(await store.checkPin('5678'), isTrue);
      expect(await store.checkPin('1234'), isFalse);
      expect(await store.checkRecoveryCode(newCode), isTrue);
      expect(await store.checkRecoveryCode(oldCode), isFalse);
    },
  );

  test('a pin that is not 4 digits is refused', () async {
    expect(() => store.setPin('123'), throwsArgumentError);
    expect(() => store.setPin('12ab'), throwsArgumentError);
    expect(await store.hasPin(), isFalse);
  });

  group('recovery email', () {
    Future<List<Map<String, Object?>>> recoveryEmails() {
      return db.query('outbox', where: "kind = 'recovery'");
    }

    test('no owner email, no recovery email', () async {
      await store.setPin('1234');

      expect(await recoveryEmails(), isEmpty);
    });

    test('with an owner email, the new code is queued', () async {
      await db.insert('app_settings', {
        'key': EmailSettingsStore.ownerEmailKey,
        'value': 'owner@example.com',
      });

      final code = await store.setPin('1234');

      final email = (await recoveryEmails()).single;
      expect(email['status'], 'queued');
      expect(email['day_id'], isNull);
      expect(email['html_body'], contains(code));
    });

    test(
      'a new pin replaces the unsent email, its code stopped working',
      () async {
        await db.insert('app_settings', {
          'key': EmailSettingsStore.ownerEmailKey,
          'value': 'owner@example.com',
        });
        final oldCode = await store.setPin('1234');

        final newCode = await store.setPin('5678');

        final email = (await recoveryEmails()).single;
        expect(email['html_body'], contains(newCode));
        expect(email['html_body'], isNot(contains(oldCode)));
      },
    );

    test('a sent recovery email stays in the outbox log', () async {
      await db.insert('app_settings', {
        'key': EmailSettingsStore.ownerEmailKey,
        'value': 'owner@example.com',
      });
      await store.setPin('1234');
      await db.update('outbox', {'status': 'sent', 'html_body': ''});

      await store.setPin('5678');

      expect(await recoveryEmails(), hasLength(2));
    });
  });
}
