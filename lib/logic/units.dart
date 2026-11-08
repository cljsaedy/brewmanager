// units for stock items (rule 1)
// every amount of a stock item is saved in its base unit: g, ml or pcs
// the owner can type other common units, they get changed to the base unit before saving
// weight (g) and volume (ml) are never changed into each other

// the 3 base units, .name gives the text saved in the db ('g', 'ml', 'pcs')
enum BaseUnit { g, ml, pcs }

// container = sealed count + opened level/exact amount (syrups, milk, cups)
// number = one whole number in pcs (fries packs, wings, gloves)
enum CountType { container, number }

// low-stock level is either a number of containers (below 2 packs) or an exact base amount (below 500 g)
enum LowMode { containers, exact }

// a unit the owner can type an amount in, and how many base units 1 of it is
class InputUnit {
  const InputUnit(this.label, this.baseUnit, this.factor);

  // what shows in the unit picker, like 'kg'
  final String label;
  // which base unit it turns into
  final BaseUnit baseUnit;
  // 1 of this unit = factor base units, like 1 kg = 1000 g
  final double factor;
}

// 1 oz = 29.5735 ml (fluid ounce), written as a constant so it is easy to find
const double mlPerOunce = 29.5735;

// every unit the owner can type in, grouped by the base unit they turn into
const List<InputUnit> inputUnits = [
  InputUnit('g', BaseUnit.g, 1),
  InputUnit('kg', BaseUnit.g, 1000),
  InputUnit('ml', BaseUnit.ml, 1),
  InputUnit('L', BaseUnit.ml, 1000),
  InputUnit('oz', BaseUnit.ml, mlPerOunce),
  InputUnit('pcs', BaseUnit.pcs, 1),
];

// only the units that fit this base unit, so a g item never shows ml or L in the picker
List<InputUnit> inputUnitsFor(BaseUnit base) {
  return inputUnits.where((unit) => unit.baseUnit == base).toList();
}

// finds a saved unit label, like 'kg', the base unit itself when it is null or doesnt fit
InputUnit inputUnitFor(String? label, BaseUnit base) {
  final units = inputUnitsFor(base);
  for (final unit in units) {
    if (unit.label == label) return unit;
  }
  return units.first;
}

// the other way, a base amount shown in a typed unit, like 1000 g -> 1 (kg)
double fromBaseUnit(double amount, InputUnit unit) {
  return roundAmount(amount / unit.factor);
}

// changes a typed amount into the item's base unit, like 1.5 L -> 1500 ml
// throws if the unit is the wrong kind (ml typed for a g item), since g <-> ml is not allowed
double toBaseUnit(double amount, InputUnit from, BaseUnit itemUnit) {
  if (from.baseUnit != itemUnit) {
    throw ArgumentError(
      'Cannot change ${from.label} into ${itemUnit.name}. '
      'Weight and volume are never converted.',
    );
  }
  return roundAmount(amount * from.factor);
}

// cuts an amount to 4 decimals
// needed because decimal math on computers leaves tiny leftovers, like 0.7 * 1000 = 700.0000000000001
double roundAmount(double value) {
  return (value * 10000).round() / 10000;
}
