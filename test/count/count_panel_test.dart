import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/count/count_panel.dart';
import 'package:brewmanager/count/count_badges.dart';
import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/layout/app_layout.dart';
import 'package:brewmanager/logic/count_math.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/widgets/status_chip.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

const StockItem syrup = StockItem(
  name: 'Caramel syrup',
  category: 'Syrups',
  baseUnit: BaseUnit.ml,
  countType: CountType.container,
  containerLabel: 'bottle',
  containerSize: 2000,
  lowMode: LowMode.containers,
  lowValue: 1,
);

const StockItem friesPack = StockItem(
  name: 'Fries pack',
  category: 'Food',
  baseUnit: BaseUnit.pcs,
  countType: CountType.number,
  lowMode: LowMode.exact,
  lowValue: 5,
);

void main() {
  late Database db;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
  });

  tearDown(() async {
    await db.close();
  });

  // the screen reads and saves on its own, so give it real time
  Future<void> waitForDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  // adds the item, opens the app the real way and taps the item's row
  Future<void> openPanel(WidgetTester tester, StockItem item) async {
    useTabletScreen(tester);
    await tester.runAsync(() => StockItemStore(db).add(item));
    await tester.pumpWidget(
      BrewManagerApp(
        home: AppLayout(openCountStore: () async => CountStore(db)),
      ),
    );
    await waitForDb(tester);
    await tester.tap(find.text(item.name));
    await tester.pumpAndSettle();
  }

  // the one count line in the db
  Future<Map<String, Object?>> savedLine(WidgetTester tester) async {
    final rows = await tester.runAsync(() => db.query('count_lines'));
    return rows!.single;
  }

  // scrolls the panel to it and taps it
  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await waitForDb(tester);
  }

  String sealedShown(WidgetTester tester) {
    return tester.widget<Text>(find.byKey(const Key('sealed_value'))).data!;
  }

  testWidgets('no panel until a row is tapped, close hides it', (tester) async {
    await openPanel(tester, syrup);
    expect(find.byType(CountPanel), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(CountPanel), findsNothing);
  });

  testWidgets('the table keeps Unit while the panel is open', (tester) async {
    await openPanel(tester, syrup);
    expect(find.text('Unit'), findsOneWidget);
    expect(find.text('bottle'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Unit'), findsOneWidget);
    expect(find.text('bottle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a container item shows sealed and opened, no number box', (
    tester,
  ) async {
    await openPanel(tester, syrup);

    expect(find.byKey(const Key('sealed_plus')), findsOneWidget);
    expect(find.text('Almost empty'), findsOneWidget);
    expect(find.byKey(const Key('exact_field')), findsOneWidget);
    expect(find.byKey(const Key('number_field')), findsNothing);
  });

  testWidgets('a number item only shows the number box', (tester) async {
    await openPanel(tester, friesPack);

    expect(find.byKey(const Key('number_field')), findsOneWidget);
    expect(find.byKey(const Key('sealed_plus')), findsNothing);
    expect(find.text('Almost empty'), findsNothing);
    expect(find.byKey(const Key('exact_field')), findsNothing);
  });

  testWidgets('+ and - save sealed and End, it stops at 0', (tester) async {
    await openPanel(tester, syrup);

    await tapVisible(tester, find.byKey(const Key('sealed_plus')));
    await tapVisible(tester, find.byKey(const Key('sealed_plus')));
    expect(sealedShown(tester), '2');
    expect((await savedLine(tester))['end_qty'], 4000);
    expect((await savedLine(tester))['touched'], 1);

    await tapVisible(tester, find.byKey(const Key('sealed_minus')));
    await tapVisible(tester, find.byKey(const Key('sealed_minus')));
    expect(sealedShown(tester), '0');

    final minus = tester.widget<IconButton>(
      find.byKey(const Key('sealed_minus')),
    );
    expect(minus.onPressed, isNull);
  });

  testWidgets('two fast taps both count', (tester) async {
    await openPanel(tester, syrup);

    // no waiting between the taps, so the first save is not done yet
    await tester.tap(find.byKey(const Key('sealed_plus')));
    await tester.tap(find.byKey(const Key('sealed_plus')));
    await waitForDb(tester);

    expect(sealedShown(tester), '2');
    expect((await savedLine(tester))['sealed'], 2);
  });

  testWidgets('a level is estimated and says about', (tester) async {
    await openPanel(tester, syrup);

    await tapVisible(tester, find.text('50%'));

    final line = await savedLine(tester);
    expect(line['level'], level50);
    expect(line['end_qty'], 1000);
    expect(line['end_is_exact'], 0);
    expect(find.text('End: about 0.5 bottles (1,000 ml)'), findsOneWidget);
  });

  testWidgets('exact replaces the level, a level clears exact', (tester) async {
    await openPanel(tester, syrup);
    await tapVisible(tester, find.text('50%'));

    await tester.enterText(find.byKey(const Key('exact_field')), '350');
    await waitForDb(tester);
    var line = await savedLine(tester);
    expect(line['exact_qty'], 350);
    expect(line['end_qty'], 350);
    expect(line['end_is_exact'], 1);
    expect(find.text('End: 0.18 bottles (350 ml)'), findsOneWidget);

    await tapVisible(tester, find.text('25%'));
    line = await savedLine(tester);
    expect(line['exact_qty'], isNull);
    expect(line['end_qty'], 500);
    expect(line['end_is_exact'], 0);
    final box = tester.widget<TextField>(find.byKey(const Key('exact_field')));
    expect(box.controller!.text, '');
  });

  testWidgets('tapping the level already on marks the line touched', (
    tester,
  ) async {
    await openPanel(tester, syrup);
    expect((await savedLine(tester))['touched'], 0);

    await tapVisible(tester, find.text('None'));

    expect((await savedLine(tester))['touched'], 1);
  });

  testWidgets('the number box saves End and the table follows', (tester) async {
    await openPanel(tester, friesPack);

    await tester.enterText(find.byKey(const Key('number_field')), '9');
    await waitForDb(tester);

    expect((await savedLine(tester))['end_qty'], 9);
    expect(find.text('End: 9 pcs'), findsOneWidget);
  });

  testWidgets('an empty number box keeps the last number', (tester) async {
    await openPanel(tester, friesPack);
    await tester.enterText(find.byKey(const Key('number_field')), '9');
    await waitForDb(tester);

    await tester.enterText(find.byKey(const Key('number_field')), '');
    await waitForDb(tester);

    expect((await savedLine(tester))['end_qty'], 9);
  });

  testWidgets('the note saves as it is typed', (tester) async {
    await openPanel(tester, friesPack);

    await tester.enterText(find.byKey(const Key('note_field')), '2 expired');
    await waitForDb(tester);

    final line = await savedLine(tester);
    expect(line['note'], '2 expired');
    expect(line['touched'], 0);
  });

  testWidgets('the low-stock level shows its mode and saves', (tester) async {
    await openPanel(tester, syrup);

    // the restock box says bottles too, so only look inside this box
    expect(
      find.descendant(
        of: find.byKey(const Key('low_field')),
        matching: find.text('bottles'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('low_field')), '3');
    await waitForDb(tester);

    final rows = await tester.runAsync(() => db.query('stock_items'));
    expect(rows!.single['low_value'], 3);
  });

  testWidgets('the panel opens showing what was saved', (tester) async {
    await openPanel(tester, syrup);
    await tapVisible(tester, find.byKey(const Key('sealed_plus')));
    await tester.enterText(find.byKey(const Key('exact_field')), '350');
    await tester.enterText(find.byKey(const Key('note_field')), 'hello');
    await waitForDb(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caramel syrup'));
    await tester.pumpAndSettle();

    expect(sealedShown(tester), '1');
    expect(find.text('350'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });

  group('restocks', () {
    // types the amount and taps Add
    Future<void> addRestock(WidgetTester tester, String amount) async {
      await tester.enterText(find.byKey(const Key('in_field')), amount);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('in_add')));
    }

    bool addIsOn(WidgetTester tester) {
      final add = tester.widget<FilledButton>(find.byKey(const Key('in_add')));
      return add.onPressed != null;
    }

    testWidgets('a container restock adds to sealed and shows in the list', (
      tester,
    ) async {
      await openPanel(tester, syrup);

      await addRestock(tester, '2');

      expect(sealedShown(tester), '2');
      expect(find.textContaining('+2 bottles · '), findsOneWidget);
      final line = await savedLine(tester);
      expect(line['in_qty'], 4000);
      expect(line['end_qty'], 4000);
      expect(line['touched'], 0);
    });

    testWidgets('the unit next to the box follows the item', (tester) async {
      await openPanel(tester, syrup);
      await tester.ensureVisible(find.byKey(const Key('in_field')));
      await tester.pumpAndSettle();

      // the low-stock box says bottles too
      expect(find.text('bottles'), findsNWidgets(2));
    });

    testWidgets('a number restock updates the number box', (tester) async {
      await openPanel(tester, friesPack);
      await tester.enterText(find.byKey(const Key('number_field')), '3');
      await waitForDb(tester);

      await addRestock(tester, '5');

      final box = tester.widget<TextField>(
        find.byKey(const Key('number_field')),
      );
      expect(box.controller!.text, '8');
      expect(find.textContaining('+5 pcs · '), findsOneWidget);
      expect(find.text('End: 8 pcs'), findsOneWidget);
    });

    testWidgets('× takes the restock back out', (tester) async {
      await openPanel(tester, syrup);
      await addRestock(tester, '2');

      await tapVisible(tester, find.byTooltip('Remove restock'));

      expect(sealedShown(tester), '0');
      expect(find.textContaining('+2 bottles'), findsNothing);
      expect((await savedLine(tester))['in_qty'], 0);
    });

    testWidgets('a double tap on Add only adds once', (tester) async {
      await openPanel(tester, syrup);
      await tester.enterText(find.byKey(const Key('in_field')), '1');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('in_add')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('in_add')));
      await tester.tap(find.byKey(const Key('in_add')), warnIfMissed: false);
      await waitForDb(tester);

      expect(sealedShown(tester), '1');
      expect((await savedLine(tester))['in_qty'], 2000);
    });

    testWidgets('a + right after a restock keeps both', (tester) async {
      await openPanel(tester, syrup);
      await tester.enterText(find.byKey(const Key('in_field')), '2');
      await tester.pumpAndSettle();

      // calls both buttons right after each other, so the restock is not saved yet
      // they are too far apart to be on screen together, so no real taps here
      tester.widget<FilledButton>(find.byKey(const Key('in_add'))).onPressed!();
      await tester.pump();
      tester
          .widget<IconButton>(find.byKey(const Key('sealed_plus')))
          .onPressed!();
      await waitForDb(tester);

      expect(sealedShown(tester), '3');
      expect((await savedLine(tester))['sealed'], 3);
    });

    testWidgets('Add is off for an empty box or 0', (tester) async {
      await openPanel(tester, syrup);
      expect(addIsOn(tester), isFalse);

      await tester.enterText(find.byKey(const Key('in_field')), '0');
      await tester.pumpAndSettle();
      expect(addIsOn(tester), isFalse);

      await tester.enterText(find.byKey(const Key('in_field')), '1');
      await tester.pumpAndSettle();
      expect(addIsOn(tester), isTrue);
    });

    testWidgets('restocks are still there when the panel opens again', (
      tester,
    ) async {
      await openPanel(tester, syrup);
      await addRestock(tester, '1');

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caramel syrup'));
      await tester.pumpAndSettle();

      expect(find.textContaining('+1 bottle · '), findsOneWidget);
    });
  });

  group('container finished', () {
    final finish = find.byKey(const Key('out_finish'));
    final undo = find.byKey(const Key('out_undo'));
    final plus = find.byKey(const Key('sealed_plus'));

    String finishedShown(WidgetTester tester) {
      return tester.widget<Text>(find.byKey(const Key('out_value'))).data!;
    }

    testWidgets('a number item has no OUT part', (tester) async {
      await openPanel(tester, friesPack);
      expect(finish, findsNothing);
    });

    testWidgets('the message says what the tap changed', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      await tapVisible(tester, plus);
      await tapVisible(tester, find.text('50%'));

      await tapVisible(tester, finish);
      expect(
        find.text('Bottle finished. Sealed 2 → 1, Opened: Full.'),
        findsOneWidget,
      );

      await tapVisible(tester, undo);
      expect(find.text('Undone. Sealed 1 → 2, Opened: 50%.'), findsOneWidget);
      // the new message replaces the old one
      expect(find.textContaining('Bottle finished.'), findsNothing);
    });

    testWidgets('the message leaves out sealed if it didnt change', (
      tester,
    ) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, find.text('50%'));

      await tapVisible(tester, finish);

      expect(find.text('Bottle finished. Opened: None.'), findsOneWidget);
    });

    testWidgets('the message goes away by itself', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, find.text('50%'));
      await tapVisible(tester, finish);
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('with sealed left it opens the next one', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      await tapVisible(tester, plus);
      await tapVisible(tester, find.text('50%'));

      await tapVisible(tester, finish);

      expect(sealedShown(tester), '1');
      expect(finishedShown(tester), '1');
      final line = await savedLine(tester);
      expect(line['out_count'], 1);
      expect(line['level'], levelFull);
      expect(line['end_qty'], 4000);
    });

    testWidgets('with no sealed left nothing stays open', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, find.text('50%'));

      await tapVisible(tester, finish);

      final line = await savedLine(tester);
      expect(line['out_count'], 1);
      expect(line['level'], levelNone);
      expect(line['end_qty'], 0);
    });

    testWidgets('undo puts back the typed exact amount', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      await tester.enterText(find.byKey(const Key('exact_field')), '350');
      await waitForDb(tester);

      await tapVisible(tester, finish);
      TextField box() {
        return tester.widget<TextField>(find.byKey(const Key('exact_field')));
      }

      expect(box().controller!.text, '');

      await tapVisible(tester, undo);

      expect(box().controller!.text, '350');
      expect(sealedShown(tester), '1');
      expect(finishedShown(tester), '0');
      final line = await savedLine(tester);
      expect(line['exact_qty'], 350);
      expect(line['end_qty'], 2350);
    });

    testWidgets('undo is off until something is finished', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      bool undoIsOn() => tester.widget<IconButton>(undo).onPressed != null;

      expect(undoIsOn(), isFalse);
      await tapVisible(tester, finish);
      expect(undoIsOn(), isTrue);
    });

    testWidgets('undo keeps a level changed after the tap', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      await tapVisible(tester, finish);
      await tapVisible(tester, find.text('25%'));

      await tapVisible(tester, undo);

      expect(sealedShown(tester), '1');
      final line = await savedLine(tester);
      expect(line['level'], level25);
      expect(line['out_count'], 0);
    });

    testWidgets('undo keeps a restock made after the tap', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      await tapVisible(tester, finish);
      await tester.enterText(find.byKey(const Key('in_field')), '1');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('in_add')));

      await tapVisible(tester, undo);

      expect(sealedShown(tester), '2');
      expect((await savedLine(tester))['in_qty'], 2000);
    });

    testWidgets('nothing open turns the button off and shows the hint', (
      tester,
    ) async {
      await openPanel(tester, syrup);
      bool finishIsOn() {
        return tester.widget<OutlinedButton>(finish).onPressed != null;
      }

      expect(finishIsOn(), isFalse);
      expect(find.text('Nothing open to finish.'), findsOneWidget);

      await tapVisible(tester, find.text('50%'));

      expect(finishIsOn(), isTrue);
      expect(find.text('Nothing open to finish.'), findsNothing);
    });

    testWidgets('the last container turns the button off after it', (
      tester,
    ) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, find.text('50%'));

      await tapVisible(tester, finish);

      expect(find.text('Nothing open to finish.'), findsOneWidget);
    });

    testWidgets('the button says the container name', (tester) async {
      await openPanel(tester, syrup);
      expect(find.text('Bottle finished'), findsOneWidget);
    });

    testWidgets('no container name says Container finished', (tester) async {
      const noName = StockItem(
        name: 'Beans',
        category: 'Coffee',
        baseUnit: BaseUnit.g,
        countType: CountType.container,
        containerSize: 250,
        lowMode: LowMode.containers,
        lowValue: 1,
      );
      await openPanel(tester, noName);
      expect(find.text('Container finished'), findsOneWidget);
    });

    testWidgets('two fast taps both count', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      await tester.ensureVisible(finish);
      await tester.pumpAndSettle();

      // no waiting between the taps, so the first save is not done yet
      await tester.tap(finish);
      await tester.tap(finish);
      await waitForDb(tester);

      expect(finishedShown(tester), '2');
      expect((await savedLine(tester))['out_count'], 2);
    });

    testWidgets('a fast undo right after finishing still undoes it', (
      tester,
    ) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, plus);
      await tester.ensureVisible(undo);
      await tester.pumpAndSettle();

      await tester.tap(finish);
      await tester.pump();
      await tester.tap(undo);
      await waitForDb(tester);

      expect(sealedShown(tester), '1');
      expect((await savedLine(tester))['out_count'], 0);
    });

    testWidgets(
      'the finished count is still there when the panel opens again',
      (tester) async {
        await openPanel(tester, syrup);
        await tapVisible(tester, plus);
        await tapVisible(tester, finish);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Caramel syrup'));
        await tester.pumpAndSettle();

        expect(finishedShown(tester), '1');
      },
    );
  });

  group('lines between the parts', () {
    final inPanelBody = find.descendant(
      of: find.descendant(
        of: find.byType(CountPanel),
        matching: find.byType(SingleChildScrollView),
      ),
      matching: find.byType(Divider),
    );

    testWidgets('a container item has 5 lines', (tester) async {
      await openPanel(tester, syrup);
      expect(inPanelBody, findsNWidgets(5));
    });

    testWidgets('a number item has 3 lines', (tester) async {
      await openPanel(tester, friesPack);
      expect(inPanelBody, findsNWidgets(3));
    });
  });

  group('the restock badge follows the panel', () {
    final badge = find.widgetWithText(StatusChip, restockBadge);

    testWidgets('the badge moves to the panel, then back to the row', (
      tester,
    ) async {
      final inPanel = find.descendant(
        of: find.byType(CountPanel),
        matching: badge,
      );

      await openPanel(tester, syrup);
      expect(badge, findsOneWidget);
      expect(inPanel, findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(badge, findsOneWidget);
      expect(inPanel, findsNothing);
    });

    testWidgets('other rows show no badges while the panel is open', (
      tester,
    ) async {
      await tester.runAsync(() => StockItemStore(db).add(syrup));
      await openPanel(tester, friesPack);

      // the syrup is on its opening count too but only the open item shows it
      expect(badge, findsOneWidget);
      expect(find.text(openingCountBadge), findsOneWidget);
    });

    testWidgets('the keyboard hides the panel badges', (tester) async {
      await openPanel(tester, syrup);

      tester.view.viewInsets = const FakeViewPadding(bottom: 400);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(badge, findsNothing);
      expect(find.byType(CountPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a higher count takes it away', (tester) async {
      await openPanel(tester, syrup);
      expect(badge, findsOneWidget);

      // 2 bottles is above the low level of 1
      await tapVisible(tester, find.byKey(const Key('sealed_plus')));
      await tapVisible(tester, find.byKey(const Key('sealed_plus')));

      expect(badge, findsNothing);
    });

    testWidgets('a new low-stock level changes it right away', (tester) async {
      await openPanel(tester, syrup);
      await tapVisible(tester, find.byKey(const Key('sealed_plus')));
      await tapVisible(tester, find.byKey(const Key('sealed_plus')));
      expect(badge, findsNothing);

      await tester.enterText(find.byKey(const Key('low_field')), '3');
      await waitForDb(tester);

      expect(badge, findsOneWidget);
    });

    testWidgets('the panel stays open when its row leaves the filter', (
      tester,
    ) async {
      await openPanel(tester, syrup);
      await tester.tap(find.byKey(const Key('filter_restock')));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byKey(const Key('sealed_plus')));
      await tapVisible(tester, find.byKey(const Key('sealed_plus')));

      expect(find.text('No items need restocking'), findsOneWidget);
      expect(find.byType(CountPanel), findsOneWidget);
    });
  });

  testWidgets('tapping another row shows that item', (tester) async {
    await openPanel(tester, syrup);
    await tester.runAsync(() => StockItemStore(db).add(friesPack));
    await tester.tap(find.byKey(const Key('sealed_plus')));
    await waitForDb(tester);

    await tester.tap(find.text('Fries pack'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('number_field')), findsOneWidget);
  });
}
