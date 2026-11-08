import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/owner_pin_store.dart';
import 'package:brewmanager/logic/business_day.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/security/key_store.dart';
import 'package:brewmanager/setup/setup_wizard.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late MemoryKeyStore keys;
  // how many emails the fake mailjet got
  late int mailjetCalls;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    keys = MemoryKeyStore();
    mailjetCalls = 0;
  });

  tearDown(() async {
    await db.close();
  });

  http.Client mailjetOk() {
    return MockClient((_) async {
      mailjetCalls++;
      return http.Response('{"Messages":[{"Status":"success"}]}', 200);
    });
  }

  // real db work only moves on while the test waits in real time, so it waits in short rounds
  Future<void> waitForDb(WidgetTester tester) async {
    for (var round = 0; round < 10; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> openApp(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(
        home: StartScreen(
          openDatabase: () async => db,
          keys: keys,
          httpClient: mailjetOk(),
          // the real count tab is tested elsewhere, this marks that the wizard is done
          barista: () => const Scaffold(body: Text('Count tab')),
        ),
      ),
    );
    await waitForDb(tester);
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.byKey(Key('pin_key_$digit')));
      await tester.pump();
    }
    await waitForDb(tester);
  }

  // welcome, then the pin twice, then "I saved it"
  Future<void> doPinStep(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('wizard_start')));
    await tester.pumpAndSettle();
    await typePin(tester, '1234');
    await typePin(tester, '1234');
    await tester.tap(find.text('I saved it'));
    await waitForDb(tester);
  }

  testWidgets('with a pin already set, the app opens straight to counting', (
    tester,
  ) async {
    await OwnerPinStore(db).setPin('1234');

    await openApp(tester);

    expect(find.text('Count tab'), findsOneWidget);
    expect(find.text('Welcome to BrewManager'), findsNothing);
  });

  testWidgets('a fresh install runs the 3 steps', (tester) async {
    await openApp(tester);
    expect(find.text('Welcome to BrewManager'), findsOneWidget);

    await doPinStep(tester);
    // step 2, the emails and keys
    expect(find.text('Emails & keys'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('owner_email_field')),
      'owner@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sender_email_field')),
      'reports@example.com',
    );
    await tester.enterText(
      find.byKey(Key('${ApiKey.mailjetKey.storageName}_field')),
      'test-key',
    );
    await tester.enterText(
      find.byKey(Key('${ApiKey.mailjetSecret.storageName}_field')),
      'test-secret',
    );
    await tester.tap(find.byKey(const Key('save_settings')));
    await waitForDb(tester);

    // step 3, the first count date, today by default
    expect(find.text('First count date'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wizard_finish')));
    await waitForDb(tester);

    expect(find.text('Count tab'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await OwnerPinStore(db).checkPin('1234'), isTrue);
      final date = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [CountStore.firstCountDateKey],
      );
      expect(date.single['value'], dateText(DateTime.now()));
      // the code from step 1 was emailed once the owner email was saved, and sent right away
      final recovery = await db.query('outbox', where: "kind = 'recovery'");
      expect(recovery.single['status'], 'sent');
    });
    expect(mailjetCalls, 1);
  });

  testWidgets('skipping emails sends nothing', (tester) async {
    await openApp(tester);
    await doPinStep(tester);

    await tester.tap(find.byKey(const Key('wizard_skip')));
    await waitForDb(tester);

    expect(find.text('First count date'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await db.query('outbox'), isEmpty);
    });
    expect(mailjetCalls, 0);
  });

  testWidgets('back does nothing after the pin is set', (tester) async {
    await openApp(tester);
    await doPinStep(tester);

    // the android back button
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Emails & keys'), findsOneWidget);
  });
}
