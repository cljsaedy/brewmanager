import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/owner_pin_store.dart';
import 'package:brewmanager/layout/app_layout.dart';
import 'package:brewmanager/theme/app_theme.dart';
import 'package:brewmanager/widgets/pin_pad.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late OwnerPinStore store;

  setUp(() async {
    // the settings tab reads the keys, a test has no android secure storage so it gets an empty fake one
    FlutterSecureStorage.setMockInitialValues({});
    db = await openTestDatabase(noIsolate: true);
    store = OwnerPinStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  // shows the barista side, using the test database for the pin
  Future<void> openApp(WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppLayout(
          openPinStore: () async => store,
          openCountStore: () async => CountStore(db),
        ),
      ),
    );
  }

  // saves a pin before the test starts, gives back the recovery code
  // runAsync = do real async work (the database) outside the widget test's fake clock
  Future<String> savePin(WidgetTester tester, String pin) async {
    return (await tester.runAsync(() => store.setPin(pin)))!;
  }

  // taps the digits on the pin pad, then waits for screens to finish changing
  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.byKey(Key('pin_key_$digit')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapOwner(WidgetTester tester) async {
    await tester.tap(find.text('Owner'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'first time: create pin, see recovery code, open owner section, lock',
    (tester) async {
      await openApp(tester);
      await tapOwner(tester);
      expect(find.text('Create owner PIN'), findsOneWidget);

      await typePin(tester, '1234');
      expect(find.text('Confirm owner PIN'), findsOneWidget);

      await typePin(tester, '1234');
      expect(find.text('Save your recovery code'), findsOneWidget);
      // the code like 7KQ2-M9XA is shown
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$').hasMatch(w.data ?? ''),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('I saved it'));
      await tester.pumpAndSettle();
      expect(find.text('Lock and exit'), findsOneWidget);
      // barista top bar is hidden in the owner section
      expect(find.text('Submit'), findsNothing);

      await tester.tap(find.text('Lock and exit'));
      await tester.pumpAndSettle();
      expect(find.text('Logbook'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);

      expect(await tester.runAsync(() => store.checkPin('1234')), isTrue);
    },
  );

  testWidgets('confirm pin that doesnt match starts over', (tester) async {
    await openApp(tester);
    await tapOwner(tester);

    await typePin(tester, '1234');
    await typePin(tester, '9999');

    expect(find.text('Create owner PIN'), findsOneWidget);
    expect(find.text("The PINs didn't match. Start again."), findsOneWidget);
  });

  testWidgets('recovery code screen cant be skipped with back', (tester) async {
    await openApp(tester);
    await tapOwner(tester);
    await typePin(tester, '1234');
    await typePin(tester, '1234');

    // handlePopRoute = same as pressing the android back button
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Save your recovery code'), findsOneWidget);
  });

  testWidgets('wrong pin shows an error, right pin opens the owner section', (
    tester,
  ) async {
    await savePin(tester, '1234');
    await openApp(tester);
    await tapOwner(tester);
    expect(find.text('Owner PIN'), findsOneWidget);

    await typePin(tester, '1111');
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);

    await typePin(tester, '1234');
    expect(find.text('Lock and exit'), findsOneWidget);
  });

  testWidgets('back button locks the owner section', (tester) async {
    await savePin(tester, '1234');
    await openApp(tester);
    await tapOwner(tester);
    await typePin(tester, '1234');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Logbook'), findsOneWidget);

    // opening again asks for the pin again
    await tapOwner(tester);
    expect(find.text('Owner PIN'), findsOneWidget);
  });

  testWidgets('app going to the background locks the owner section', (
    tester,
  ) async {
    await savePin(tester, '1234');
    await openApp(tester);
    await tapOwner(tester);
    await typePin(tester, '1234');
    expect(find.text('Lock and exit'), findsOneWidget);

    // same as pressing home: the app goes inactive, then hidden
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    // then the owner comes back to the app
    // (flutter doesnt draw frames while hidden, so the screen only updates after this)
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Logbook'), findsOneWidget);
    expect(find.text('Lock and exit'), findsNothing);
  });

  testWidgets('forgot pin: recovery code lets the owner make a new pin', (
    tester,
  ) async {
    final code = await savePin(tester, '1234');
    await openApp(tester);
    await tapOwner(tester);

    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();

    // wrong code first
    await tester.enterText(find.byType(TextField), 'AAAA-AAAA');
    await tester.tap(find.text('Check code'));
    await tester.pumpAndSettle();
    expect(
      find.text('That code is not right. Check it and try again.'),
      findsOneWidget,
    );

    // right code, typed in lowercase
    await tester.enterText(find.byType(TextField), code.toLowerCase());
    await tester.tap(find.text('Check code'));
    await tester.pumpAndSettle();
    expect(find.text('Create owner PIN'), findsOneWidget);

    await typePin(tester, '5678');
    await typePin(tester, '5678');
    expect(find.text('Save your recovery code'), findsOneWidget);

    expect(await tester.runAsync(() => store.checkPin('5678')), isTrue);
    expect(await tester.runAsync(() => store.checkRecoveryCode(code)), isFalse);
  });

  testWidgets('pin pad backspace removes the last digit', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PinPad(onCompleted: (pin) => result = pin)),
      ),
    );

    await typePin(tester, '12');
    await tester.tap(find.byKey(const Key('pin_backspace')));
    await tester.pump();
    await typePin(tester, '345');

    expect(result, '1345');
  });
}
