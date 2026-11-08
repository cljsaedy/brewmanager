import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/logic/units.dart';

// how a stock item's amounts show on screens, the typed unit and the piece name are display only
void main() {
  // 1 kg low level, saved as 1000 g
  const beans = StockItem(
    name: 'Coffee beans',
    category: 'Beans',
    baseUnit: BaseUnit.g,
    countType: CountType.container,
    containerLabel: 'bag',
    containerSize: 2000,
    sizeUnit: 'kg',
    lowMode: LowMode.exact,
    lowValue: 1000,
    lowUnit: 'kg',
  );

  const fries = StockItem(
    name: 'Fries pack',
    category: 'Food',
    baseUnit: BaseUnit.pcs,
    countType: CountType.number,
    containerLabel: 'pack',
    lowMode: LowMode.exact,
    lowValue: 5,
  );

  group('typed units', () {
    test('size and low level show in the typed unit', () {
      expect(beans.sizeText, '2 kg');
      expect(beans.lowText, '1 kg');
      expect(beans.lowShown, 1);
      expect(beans.lowWord, 'kg');
    });

    test('a number typed in the low box goes back to the base unit', () {
      expect(beans.lowFromShown(0.5), 500);
    });

    test('oz goes there and back without leftovers', () {
      const syrup = StockItem(
        name: 'Syrup',
        category: 'Syrups',
        baseUnit: BaseUnit.ml,
        countType: CountType.container,
        containerSize: 750,
        lowMode: LowMode.exact,
        lowValue: 59.147,
        lowUnit: 'oz',
      );

      expect(syrup.lowShown, 2);
      expect(syrup.lowText, '2 oz');
    });

    test('no saved unit shows the base unit like before', () {
      const plain = StockItem(
        name: 'Milk',
        category: 'Milk',
        baseUnit: BaseUnit.ml,
        countType: CountType.container,
        containerSize: 1000,
        lowMode: LowMode.exact,
        lowValue: 500,
      );

      expect(plain.sizeText, '1,000 ml');
      expect(plain.lowText, '500 ml');
      expect(plain.lowWord, 'ml');
    });

    test('containers mode keeps the container word', () {
      final item = beans.copyWith(lowMode: LowMode.containers, lowValue: 2);

      expect(item.lowText, '2 bags');
      expect(item.lowWord, 'bags');
      expect(item.lowFromShown(3), 3);
    });
  });

  group('piece name', () {
    test('a number item shows its piece name', () {
      expect(fries.pieceName, 'pack');
      expect(fries.unitWord, 'packs');
      expect(fries.lowText, '5 packs');
      expect(amountText(fries, 1), '1 pack');
    });

    test('no piece name shows pcs', () {
      const plain = StockItem(
        name: 'Gloves',
        category: 'Supplies',
        baseUnit: BaseUnit.pcs,
        countType: CountType.number,
        lowMode: LowMode.exact,
        lowValue: 10,
      );

      expect(plain.pieceName, isNull);
      expect(plain.unitWord, 'pcs');
      expect(amountText(plain, 6), '6 pcs');
    });

    test('container items still show the base unit for amounts', () {
      expect(beans.unitWord, 'g');
      expect(amountText(beans, 250), '250 g');
    });
  });
}
