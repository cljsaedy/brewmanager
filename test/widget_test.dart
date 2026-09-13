import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/main.dart';

void main() {
  testWidgets('App builds with the given home screen', (tester) async {
    await tester.pumpWidget(
      const BrewManagerApp(home: Scaffold(body: Text('hello'))),
    );

    expect(find.text('hello'), findsOneWidget);
  });
}
