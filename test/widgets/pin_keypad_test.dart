import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/widgets/pin_keypad.dart';

void main() {
  Future<void> pumpKeypad(
    WidgetTester tester,
    void Function(String) onCompleted, {
    String? error,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinKeypad(onCompleted: onCompleted, errorMessage: error),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.widgetWithText(FilledButton, key));
    await tester.pump();
  }

  testWidgets('fires onCompleted with the four digits tapped', (tester) async {
    String? result;
    await pumpKeypad(tester, (pin) => result = pin);

    for (final d in ['1', '2', '3', '4']) {
      await tap(tester, d);
    }

    expect(result, '1234');
  });

  testWidgets('backspace removes the last digit', (tester) async {
    String? result;
    await pumpKeypad(tester, (pin) => result = pin);

    await tap(tester, '1');
    await tap(tester, '2');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    await tap(tester, '9');
    await tap(tester, '9');
    await tap(tester, '9');

    expect(result, '1999');
  });

  testWidgets('shows the error message when given one', (tester) async {
    await pumpKeypad(tester, (_) {}, error: 'Incorrect PIN');
    expect(find.text('Incorrect PIN'), findsOneWidget);
  });
}
