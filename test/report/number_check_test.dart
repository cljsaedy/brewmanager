import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/report/number_check.dart';

void main() {
  // a small facts text like the one the ai gets
  const facts =
      '{"date":"Mon, Nov 2","menu_items_tallied":14,'
      '"exact_items":[{"item":"Fries pack","used":3,"expected":2,"gap":1,"unit":"packs"},'
      '{"item":"Ice","used":480,"expected":500,"gap":-20,"unit":"g"}],'
      '"container_checks":[{"item":"Caramel syrup","containers_finished":1,'
      '"total_used":1700,"recipes_explain":1650.5,"since":"Nov 1","unit":"ml"}],'
      '"day_note":"two packs dropped at 3pm"}';

  group('good texts pass', () {
    test('every number copied from the facts', () {
      final check = checkNumbers(
        'On Mon, Nov 2, 14 menu items were tallied. Fries pack used 3 packs '
        'against 2 expected, a gap of 1. Caramel syrup finished 1 bottle '
        '(1700 ml); recipes explain 1650.5 ml since Nov 1.',
        facts,
      );

      expect(check.passed, isTrue);
    });

    test('a comma in a number is only formatting', () {
      expect(checkNumbers('1,700 ml finished.', facts).passed, isTrue);
    });

    test('a sign is ignored, a gap of -20 can be said as 20 less', () {
      expect(checkNumbers('Ice used 20 g less.', facts).passed, isTrue);
      expect(checkNumbers('Ice gap: −20 g.', facts).passed, isTrue);
    });

    test('a number word quoted from a note is fine', () {
      expect(
        checkNumbers('Day note: "two packs dropped at 3pm".', facts).passed,
        isTrue,
      );
    });

    test('words that only contain a number word are not number words', () {
      expect(
        checkNumbers('Nothing else was done. Someone phoned.', facts).passed,
        isTrue,
      );
    });
  });

  group('bad texts fail', () {
    test('a number that is not in the facts', () {
      final check = checkNumbers('Fries pack used 4 packs.', facts);

      expect(check.passed, isFalse);
      expect(check.mismatches, ['4']);
    });

    test('a rounded number', () {
      final check = checkNumbers('Recipes explain about 1,651 ml.', facts);

      expect(check.mismatches, ['1,651']);
    });

    test('a number word the facts dont have', () {
      final check = checkNumbers('Fries pack used three packs.', facts);

      expect(check.mismatches, ['three']);
    });

    test('words for amounts count too', () {
      expect(checkNumbers('About half a bottle.', facts).passed, isFalse);
      expect(checkNumbers('A dozen lattes.', facts).passed, isFalse);
      expect(checkNumbers('One item needs restocking.', facts).passed, isFalse);
    });

    test('a year the facts never gave', () {
      expect(checkNumbers('Mon, Nov 2, 2026.', facts).passed, isFalse);
    });

    test('a number worked out by the ai (2 + 1)', () {
      expect(checkNumbers('Fries used 5 packs in all.', facts).passed, isFalse);
    });
  });

  test('numbersIn reads commas and decimals', () {
    expect(numbersIn('1,700 and 2.96 and 12,500.5 and 7'), [
      1700,
      2.96,
      12500.5,
      7,
    ]);
  });
}
