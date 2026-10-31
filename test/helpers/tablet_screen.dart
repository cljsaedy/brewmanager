import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

// makes the fake test screen the same as the tablet: 1340 x 800 pixels, landscape
// (flutter tests use a 800 x 600 screen by default which is not our tablet)
void useTabletScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1340, 800);
  tester.view.devicePixelRatio = 1.5;
  // put the screen back to normal after each test
  addTearDown(tester.view.reset);
}
