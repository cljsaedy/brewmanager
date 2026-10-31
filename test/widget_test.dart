import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/main.dart';

void main() {
  // checks the app opens without crashing and shows the app name
  testWidgets('app starts and shows BrewManager', (WidgetTester tester) async {
    await tester.pumpWidget(const BrewManagerApp());

    expect(find.text('BrewManager'), findsOneWidget);
  });
}
