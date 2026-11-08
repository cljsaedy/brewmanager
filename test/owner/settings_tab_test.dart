import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/email_settings_store.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/owner/settings/settings_tab.dart';
import 'package:brewmanager/security/key_store.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late MemoryKeyStore keys;
  late EmailSettingsStore store;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    keys = MemoryKeyStore();
    store = EmailSettingsStore(db, keys);
  });

  tearDown(() async {
    await db.close();
  });

  // the tab reads the db on its own, so give it real time
  Future<void> waitForDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(
        home: Scaffold(body: SettingsTab(store: store)),
      ),
    );
    await waitForDb(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('save_settings')));
    await waitForDb(tester);
  }

  testWidgets('saves emails and keys, the key box empties after', (
    tester,
  ) async {
    await openSettings(tester);
    expect(find.text('Not set.'), findsNWidgets(3));

    await tester.enterText(
      find.byKey(const Key('owner_email_field')),
      'owner@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('sender_email_field')),
      'reports@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('groq_api_key_field')),
      'test-groq-value',
    );
    await save(tester);

    expect(find.text('Saved.'), findsOneWidget);
    expect(keys.values[ApiKey.groqKey], 'test-groq-value');
    expect(find.text('Saved. Type a new one to replace it.'), findsOneWidget);
    // the key is never shown back
    final box = tester.widget<TextField>(
      find.byKey(const Key('groq_api_key_field')),
    );
    expect(box.controller!.text, isEmpty);
    expect(find.text('test-groq-value'), findsNothing);

    late EmailSettings saved;
    await tester.runAsync(() async => saved = await store.load());
    expect(saved.ownerEmail, 'owner@example.com');
  });

  testWidgets('an empty key box keeps the saved key', (tester) async {
    keys.values[ApiKey.mailjetKey] = 'test-old-value';
    await openSettings(tester);

    await save(tester);

    expect(keys.values[ApiKey.mailjetKey], 'test-old-value');
  });

  testWidgets('a wrong email shows a message and saves nothing', (
    tester,
  ) async {
    await openSettings(tester);

    await tester.enterText(
      find.byKey(const Key('owner_email_field')),
      'owner at example',
    );
    await tester.enterText(
      find.byKey(const Key('groq_api_key_field')),
      'test-groq-value',
    );
    await save(tester);

    expect(
      find.text('"owner at example" does not look like an email.'),
      findsOneWidget,
    );
    expect(keys.values, isEmpty);
  });

  testWidgets('remove asks first, then removes the key', (tester) async {
    keys.values[ApiKey.groqKey] = 'test-groq-value';
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('groq_api_key_remove')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Reports will use the template summary until a new key is saved.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm_remove')));
    await waitForDb(tester);

    expect(keys.values, isEmpty);
    expect(find.text('Not set.'), findsNWidgets(3));
  });
}
