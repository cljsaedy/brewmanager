import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/export_rows.dart';
import 'package:brewmanager/models/loss_record.dart';

void main() {
  group('ExportRows.materialLoss', () {
    test('starts with a header row', () {
      final rows = ExportRows.materialLoss([]);

      expect(rows.length, 1);
      expect(rows.first.first, 'Date');
      expect(rows.first, contains('Category'));
      expect(rows.first, contains('Containers Equivalent'));
    });

    test('one row per loss with the category spelled out', () {
      final rows = ExportRows.materialLoss([
        LossRecord(
          occurredAt: DateTime(2026, 10, 3, 14, 30),
          ingredientId: 1,
          ingredientName: 'Fresh Milk',
          unitOfMeasure: 'ml',
          category: LossCategory.declared,
          quantity: 1000,
          containersEquivalent: 1,
        ),
        LossRecord(
          occurredAt: DateTime(2026, 10, 4, 9, 0),
          ingredientId: 2,
          ingredientName: 'Espresso Beans',
          unitOfMeasure: 'g',
          category: LossCategory.unexplained,
          quantity: 250,
          containersEquivalent: 0.25,
        ),
      ]);

      expect(rows.length, 3); // header plus two

      expect(rows[1][0], '2026-10-03'); // date only, no time
      expect(rows[1][1], 'Fresh Milk');
      expect(rows[1][2], 'Declared loss');
      expect(rows[1][3], 1000);
      expect(rows[1][4], 'ml');

      expect(rows[2][2], 'Unexplained');
      expect(rows[2][5], 0.25);
    });

    test('container equivalents are rounded to something readable', () {
      final rows = ExportRows.materialLoss([
        LossRecord(
          occurredAt: DateTime(2026, 10, 3),
          ingredientId: 1,
          ingredientName: 'Fresh Milk',
          unitOfMeasure: 'ml',
          category: LossCategory.declared,
          quantity: 250,
          // 250 of a 750ml container is 0.3333...
          containersEquivalent: 250 / 750,
        ),
      ]);

      expect(rows[1][5], 0.333);
    });
  });

  group('ExportRows.reconciliation', () {
    test('carries the expected against counted figures', () {
      final rows = ExportRows.reconciliation([
        {
          'shift_id': 3,
          'closed_at': '2026-10-10T18:00:00',
          'batch_id': 7,
          'ingredient_name': 'Espresso Beans',
          'unit_of_measure': 'g',
          'expiry_date': '2026-11-01',
          'theoretical_quantity': 1000.0,
          'audited_quantity': 750.0,
          'variance': -250.0,
          'variance_type': 'unexplained',
        },
      ]);

      expect(rows.first, contains('Theoretical Quantity'));
      expect(rows.first, contains('Audited Quantity'));
      // trimmed to minutes, the stored value carries microseconds
      expect(rows[1][1], '2026-10-10 18:00');
      expect(rows[1][6], 1000.0);
      expect(rows[1][7], 750.0);
      expect(rows[1][8], -250.0);
      expect(rows[1][9], 'unexplained');
    });

    test('a shift with no close time exports an empty cell not null', () {
      final rows = ExportRows.reconciliation([
        {
          'shift_id': 1,
          'closed_at': null,
          'batch_id': 1,
          'ingredient_name': 'Fresh Milk',
          'unit_of_measure': 'ml',
          'expiry_date': '2026-11-01',
          'theoretical_quantity': 100.0,
          'audited_quantity': 100.0,
          'variance': 0.0,
          'variance_type': 'unexplained',
        },
      ]);

      expect(rows[1][1], '');
    });
  });

  group('ExportRows.suggestions', () {
    test('acceptance reads as yes or no rather than 1 or 0', () {
      final rows = ExportRows.suggestions([
        {
          'suggested_at': '2026-10-10T09:00:00',
          'shift_id': 2,
          'menu_item_name': 'Mocha',
          'batch_id': 4,
          'ingredient_name': 'Chocolate Syrup',
          'expiry_risk_score': 1.0,
          'popularity_score': 0.5,
          'combined_score': 0.8,
          'was_accepted': 1,
        },
        {
          'suggested_at': '2026-10-11T09:00:00',
          'shift_id': 3,
          'menu_item_name': 'Latte',
          'batch_id': 1,
          'ingredient_name': 'Fresh Milk',
          'expiry_risk_score': 0.5,
          'popularity_score': 1.0,
          'combined_score': 0.7,
          'was_accepted': 0,
        },
      ]);

      expect(rows[1][8], 'Yes');
      expect(rows[2][8], 'No');
      // the three score columns the weighting comparison needs
      expect(rows[1][5], 1.0);
      expect(rows[1][6], 0.5);
      expect(rows[1][7], 0.8);
    });
  });

  group('ExportRows.sales', () {
    test('uses the snapshot price and flags voided sales', () {
      final rows = ExportRows.sales([
        {
          'transaction_datetime': '2026-10-10T09:00:00',
          'transaction_id': 11,
          'shift_id': 2,
          'cashier_name': 'Test Barista',
          'menu_item_name': 'Latte',
          'quantity': 2,
          'unit_price_at_sale': 120.0,
          'line_total': 240.0,
          'is_voided': 0,
        },
        {
          'transaction_datetime': '2026-10-10T10:00:00',
          'transaction_id': 12,
          'shift_id': 2,
          'cashier_name': 'Test Barista',
          'menu_item_name': 'Mocha',
          'quantity': 1,
          'unit_price_at_sale': 135.0,
          'line_total': 135.0,
          'is_voided': 1,
        },
      ]);

      expect(rows.first, contains('Unit Price At Sale'));
      expect(rows[1][6], 120.0);
      expect(rows[1][8], 'No');
      expect(rows[2][8], 'Yes');
    });
  });

  group('ExportRows.inventory', () {
    test('carries the five fields chapter 3 names, plus batch and unit', () {
      final rows = ExportRows.inventory([
        {
          'batch_id': 4,
          'ingredient_name': 'Fresh Milk',
          'unit_of_measure': 'ml',
          'expiry_date': '2026-10-24',
          'container_capacity': 1000.0,
          'containers_received': 6,
          'quantity_remaining': 6000.0,
        },
      ]);

      expect(rows.first, [
        'Batch',
        'Ingredient',
        'Unit',
        'Expiry Date',
        'Container Capacity',
        'Containers Received',
        'Quantity Remaining',
      ]);

      expect(rows[1][0], 4);
      expect(rows[1][1], 'Fresh Milk');
      // a quantity with no unit cannot be read, so the unit travels with it
      expect(rows[1][2], 'ml');
      expect(rows[1][3], '2026-10-24');
      expect(rows[1][4], 1000.0);
      expect(rows[1][5], 6);
      expect(rows[1][6], 6000.0);
    });

    test('an empty stock room still produces a header row', () {
      final rows = ExportRows.inventory([]);

      // a file with only headers is a valid answer to "what is in stock"
      expect(rows.length, 1);
      expect(rows.first, contains('Quantity Remaining'));
    });

    test('one row per batch, not per ingredient', () {
      final rows = ExportRows.inventory([
        {
          'batch_id': 1,
          'ingredient_name': 'Fresh Milk',
          'unit_of_measure': 'ml',
          'expiry_date': '2026-10-20',
          'container_capacity': 1000.0,
          'containers_received': 2,
          'quantity_remaining': 1400.0,
        },
        {
          'batch_id': 2,
          'ingredient_name': 'Fresh Milk',
          'unit_of_measure': 'ml',
          'expiry_date': '2026-10-24',
          'container_capacity': 1000.0,
          'containers_received': 6,
          'quantity_remaining': 6000.0,
        },
      ]);

      // two batches of the same ingredient stay separate, because the expiry
      // date and the container size are what make a batch a batch
      expect(rows.length, 3);
      expect(rows[1][3], '2026-10-20');
      expect(rows[2][3], '2026-10-24');
    });
  });
  group('ExportRows.formatTimestamp', () {
    test('trims microseconds down to minutes', () {
      expect(
        ExportRows.formatTimestamp('2026-10-04T01:23:59.521840'),
        '2026-10-04 01:23',
      );
    });

    test('pads single digit parts', () {
      expect(
        ExportRows.formatTimestamp('2026-01-02T03:04:05'),
        '2026-01-02 03:04',
      );
    });

    test('null becomes an empty cell, not the word null', () {
      expect(ExportRows.formatTimestamp(null), '');
    });

    test('something unparseable is passed through rather than lost', () {
      expect(ExportRows.formatTimestamp('not a date'), 'not a date');
    });
  });

  group('ExportRows.roundTo', () {
    test('rounds to the given places', () {
      expect(ExportRows.roundTo(1 / 3, 3), 0.333);
      expect(ExportRows.roundTo(2 / 3, 2), 0.67);
      expect(ExportRows.roundTo(5.0, 3), 5.0);
    });
  });
}
