import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/main.dart';
import 'package:brewmanager/layout/top_bar.dart';

import '../helpers/tablet_screen.dart';

void main() {
  testWidgets('opens on the Count tab with a Draft status', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp());

    // all rail buttons are there
    expect(find.text('Count'), findsOneWidget);
    expect(find.text('Tally'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);

    // count tab is the one showing, others are hidden
    expect(find.text('Count tab'), findsOneWidget);
    expect(find.text('Tally tab'), findsNothing);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('tapping Tally in the rail shows the Tally tab', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp());

    await tester.tap(find.text('Tally'));
    // pump = draw the next frame after the tap
    await tester.pump();

    expect(find.text('Tally tab'), findsOneWidget);
    expect(find.text('Count tab'), findsNothing);
  });

  testWidgets('Submit and Day Note are greyed out for now', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp());

    // a button with no onPressed is disabled
    final submit = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Submit'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    final dayNote = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Day Note'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(submit.enabled, isFalse);
    expect(dayNote.enabled, isFalse);
  });

  testWidgets('Day Note and Submit sit on the right of the top bar', (
    tester,
  ) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp());

    // getRect = where the widget is drawn on screen
    final bar = tester.getRect(find.byType(TopBar));
    final submit = tester.getRect(
      find.ancestor(
        of: find.text('Submit'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    final dayNote = tester.getRect(
      find.ancestor(
        of: find.text('Day Note'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );

    // submit ends at the right edge, only 12 px margin + 1 px border + 20 px padding between them
    expect(bar.right - submit.right, closeTo(33, 0.5));
    // day note is right before submit, 12 px gap
    expect(submit.left - dayNote.right, closeTo(12, 0.5));
  });

  testWidgets('tapping Owner shows the step 1d message', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp());

    await tester.tap(find.text('Owner'));
    await tester.pump();

    expect(find.text('Owner section comes in step 1d'), findsOneWidget);
  });
}
