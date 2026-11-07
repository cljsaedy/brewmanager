import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/formatting.dart';

void main() {
  test('capitalized makes the first letter big', () {
    expect(capitalized('bottle'), 'Bottle');
    expect(capitalized('Pack'), 'Pack');
    expect(capitalized(''), '');
  });

  test('formatTime uses small letters', () {
    expect(formatTime(DateTime(2026, 11, 1, 14, 15)), '2:15pm');
    expect(formatTime(DateTime(2026, 11, 1, 9, 5)), '9:05am');
  });

  test('amounts get commas, no .0, and at most 2 decimals', () {
    expect(formatAmount(2000), '2,000');
    expect(formatAmount(2.5), '2.5');
    expect(formatAmount(0.333), '0.33');
    expect(formatAmount(29.5735), '29.57');
    expect(formatAmount(0), '0');
  });

  test('amount with unit', () {
    expect(formatWithUnit(2000, 'ml'), '2,000 ml');
  });

  test('containers are plural unless exactly 1', () {
    expect(formatContainers(1, 'bottle'), '1 bottle');
    expect(formatContainers(2, 'bottle'), '2 bottles');
    expect(formatContainers(0.5, 'pack'), '0.5 packs');
    expect(formatContainers(2, 'box'), '2 boxes');
    expect(formatContainers(3, 'pouch'), '3 pouches');
  });
}
