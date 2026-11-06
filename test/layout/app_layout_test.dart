import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/count/count_tab.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/layout/app_layout.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/layout/top_bar.dart';

import '../helpers/loading_layout.dart';
import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  group('with a database', () {
    late Database db;

    setUp(() async {
      db = await openTestDatabase(noIsolate: true);
    });

    tearDown(() async {
      await db.close();
    });

    const StockItem friesPack = StockItem(
      name: 'Fries pack',
      category: 'Food',
      baseUnit: BaseUnit.pcs,
      countType: CountType.number,
      lowMode: LowMode.exact,
      lowValue: 5,
    );

    // the app reads the db on its own, so give it real time
    Future<void> waitForDb(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openApp(WidgetTester tester) async {
      useTabletScreen(tester);
      await tester.pumpWidget(
        BrewManagerApp(
          home: AppLayout(
            openCountStore: () async =>
                CountStore(db, clock: () => DateTime.utc(2026, 11, 1, 10)),
          ),
        ),
      );
      await waitForDb(tester);
    }

    testWidgets('the top bar shows the business date of the draft', (
      tester,
    ) async {
      await tester.runAsync(
        () => db.insert('business_days', {
          'business_date': '2026-10-30',
          'status': 'submitted',
        }),
      );
      await openApp(tester);

      // the day after the submitted day, not today
      expect(find.text('Sat, Oct 31'), findsOneWidget);
    });

    testWidgets('the logbook shows the stock items', (tester) async {
      await tester.runAsync(() => StockItemStore(db).add(friesPack));
      await openApp(tester);

      expect(find.text('Fries pack'), findsOneWidget);
      expect(find.text(openingCountBadge), findsOneWidget);
    });

    testWidgets('the logbook reloads when the owner section closes', (
      tester,
    ) async {
      await openApp(tester);
      expect(find.text('Fries pack'), findsNothing);

      // same way the real screens go: a pin screen that swaps itself for the owner section
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('pin screen')),
      );
      await tester.pumpAndSettle();
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const Text('owner section')),
      );
      await waitForDb(tester);

      // the owner adds an item after the swap, so only a reload on leaving can find it
      await tester.runAsync(() => StockItemStore(db).add(friesPack));
      navigator.pop();
      await waitForDb(tester);

      expect(find.text('Fries pack'), findsOneWidget);
    });
  });

  testWidgets('opens on the Count tab with a Draft status', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp(home: loadingLayout));

    // all rail buttons are there
    expect(find.text('Count'), findsOneWidget);
    expect(find.text('Tally'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);

    // count tab is the one showing, others are hidden
    expect(find.byType(CountTab), findsOneWidget);
    expect(find.text('Tally tab'), findsNothing);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('tapping Tally in the rail shows the Tally tab', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp(home: loadingLayout));

    await tester.tap(find.text('Tally'));
    // pump = draw the next frame after the tap
    await tester.pump();

    expect(find.text('Tally tab'), findsOneWidget);
    expect(find.byType(CountTab), findsNothing);
  });

  testWidgets('Submit and Day Note are greyed out for now', (tester) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp(home: loadingLayout));

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

  testWidgets('rail does not overflow when the keyboard is open', (
    tester,
  ) async {
    useTabletScreen(tester);
    // keyboard takes about half the screen, the scaffold shrinks the body by this much
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const BrewManagerApp(home: loadingLayout));

    // an overflow would show up here as a flutter error
    expect(tester.takeException(), isNull);
    expect(find.text('Owner'), findsOneWidget);
  });

  testWidgets('Day Note and Submit sit on the right of the top bar', (
    tester,
  ) async {
    useTabletScreen(tester);
    await tester.pumpWidget(const BrewManagerApp(home: loadingLayout));

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
}
