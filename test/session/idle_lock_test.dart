import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/models/app_user.dart';
import 'package:brewmanager/screens/pin_entry_screen.dart';
import 'package:brewmanager/session/idle_lock.dart';
import 'package:brewmanager/session/session.dart';

void main() {
  const fakeUser = AppUser(
    userId: 1,
    name: 'Test',
    role: UserRole.manager,
    isActive: true,
  );

  // same wiring as main.dart, navigatorKey + IdleLock via builder
  Widget buildApp() {
    return MaterialApp(
      navigatorKey: Session.navigatorKey,
      builder: (context, child) => IdleLock(child: child!),
      home: const Scaffold(body: Center(child: Text('HOME'))),
    );
  }

  setUp(() => Session.currentUser = null);

  testWidgets('locks after the timeout when someone is logged in',
      (tester) async {
    Session.currentUser = fakeUser;
    await tester.pumpWidget(buildApp());
    expect(find.text('HOME'), findsOneWidget);

    // fake clock, jump past the timeout without really waiting
    await tester.pump(IdleLock.timeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(Session.currentUser, isNull);
    // by type, not by wording, so copy changes don't break this
    expect(find.byType(PinEntryScreen), findsOneWidget);
  });

  testWidgets('a touch resets the countdown', (tester) async {
    Session.currentUser = fakeUser;
    await tester.pumpWidget(buildApp());

    // wait most of the timeout, touch, wait most again, total is over the timeout but no single gap is
    final mostOfIt = IdleLock.timeout - const Duration(seconds: 10);
    await tester.pump(mostOfIt);
    await tester.tap(find.text('HOME'));
    await tester.pump(mostOfIt);

    expect(Session.currentUser, fakeUser);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a suspended lock leaves a logged in user alone', (tester) async {
    Session.currentUser = fakeUser;
    IdleLock.suspend();
    addTearDown(IdleLock.resume);

    await tester.pumpWidget(buildApp());
    await tester.pump(IdleLock.timeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // the closing count asks for this, being locked out mid count loses the count
    expect(Session.currentUser, fakeUser);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('resuming restores the lock', (tester) async {
    Session.currentUser = fakeUser;
    IdleLock.suspend();
    IdleLock.resume();
    expect(IdleLock.isSuspended, isFalse);

    await tester.pumpWidget(buildApp());
    await tester.pump(IdleLock.timeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(Session.currentUser, isNull);
  });

  test('suspend counts, so nested screens cannot leave it stuck on', () {
    IdleLock.suspend();
    IdleLock.suspend();
    IdleLock.resume();
    // still held by the outer one
    expect(IdleLock.isSuspended, isTrue);

    IdleLock.resume();
    expect(IdleLock.isSuspended, isFalse);

    // extra resumes can't push it negative and disable the lock for good
    IdleLock.resume();
    expect(IdleLock.isSuspended, isFalse);
  });

  testWidgets('does nothing when no one is logged in', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.pump(IdleLock.timeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });
}
