import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/units.dart';

// finds an input unit by its label, like 'kg'
InputUnit unit(String label) =>
    inputUnits.firstWhere((unit) => unit.label == label);

void main() {
  test('kg, L and oz change into the base unit', () {
    expect(toBaseUnit(1.5, unit('kg'), BaseUnit.g), 1500);
    expect(toBaseUnit(2, unit('L'), BaseUnit.ml), 2000);
    expect(toBaseUnit(1, unit('oz'), BaseUnit.ml), 29.5735);
    expect(toBaseUnit(2, unit('oz'), BaseUnit.ml), 59.147);
  });

  test('base units stay the same', () {
    expect(toBaseUnit(250, unit('g'), BaseUnit.g), 250);
    expect(toBaseUnit(750, unit('ml'), BaseUnit.ml), 750);
    expect(toBaseUnit(50, unit('pcs'), BaseUnit.pcs), 50);
  });

  test('weight and volume are never converted', () {
    expect(() => toBaseUnit(1, unit('ml'), BaseUnit.g), throwsArgumentError);
    expect(() => toBaseUnit(1, unit('kg'), BaseUnit.ml), throwsArgumentError);
    expect(() => toBaseUnit(1, unit('oz'), BaseUnit.g), throwsArgumentError);
    expect(() => toBaseUnit(1, unit('g'), BaseUnit.pcs), throwsArgumentError);
  });

  test('the picker only shows units that fit the base unit', () {
    List<String> labels(BaseUnit base) =>
        inputUnitsFor(base).map((unit) => unit.label).toList();

    expect(labels(BaseUnit.g), ['g', 'kg']);
    expect(labels(BaseUnit.ml), ['ml', 'L', 'oz']);
    expect(labels(BaseUnit.pcs), ['pcs']);
  });

  test('tiny decimal leftovers are cut off', () {
    // 0.7 * 1000 is 700.0000000000001 without rounding
    expect(toBaseUnit(0.7, unit('kg'), BaseUnit.g), 700);
    expect(roundAmount(0.1 + 0.2), 0.3);
  });
}
