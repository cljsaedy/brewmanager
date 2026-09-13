import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/models/app_user.dart';
import 'package:brewmanager/session/idle_lock.dart';
import 'package:brewmanager/session/session.dart';

void main() {
  const fakeUser = AppUser(
    userId: 1,
    name: 'Test',
    role: UserRole.manager,
    isActive: true,
  );

  // Mirrors the wiring in main.dart: navigatorKey + IdleLock via builder.
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

    // Fake clock: advance past the timeout without really waiting.
    await tester.pump(IdleLock.timeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(Session.currentUser, isNull);
    expect(find.text('Enter your PIN to begin'), findsOneWidget);
  });

  testWidgets('a touch resets the countdown', (tester) async {
    Session.currentUser = fakeUser;
    await tester.pumpWidget(buildApp());

    // Wait most of the timeout, touch, then wait most of it again.
    // Total elapsed exceeds the timeout but no single gap does.
    final mostOfIt = IdleLock.timeout - const Duration(seconds: 10);
    await tester.pump(mostOfIt);
    await tester.tap(find.text('HOME'));
    await tester.pump(mostOfIt);

    expect(Session.currentUser, fakeUser);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('does nothing when no one is logged in', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.pump(IdleLock.timeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });
}
