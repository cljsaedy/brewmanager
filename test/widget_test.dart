import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/main.dart';

void main() {
  testWidgets('App builds and shows the BrewManager title', (tester) async {
    await tester.pumpWidget(const BrewManagerApp());

    expect(find.text('BrewManager'), findsOneWidget);
  });
}
