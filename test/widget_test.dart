import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/main.dart';

import 'helpers/tablet_screen.dart';

void main() {
  // checks the app opens without crashing and shows the app name
  testWidgets('app starts and shows BrewManager', (WidgetTester tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp());

    expect(find.text('BrewManager'), findsOneWidget);
  });
}
