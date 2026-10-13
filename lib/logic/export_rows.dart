/// turns records into rows of a table, ready for the csv encoder
///
/// pure dart with no file writing, so the shape of every export can be unit tested
/// without touching the disk
library;

import '../models/loss_record.dart';

class ExportRows {
  ExportRows._();

  /// every loss, one row each, with the category that distinguishes a known
  /// incident from mystery drift
  static List<List<Object?>> materialLoss(List<LossRecord> records) {
    return [
      [
        'Date',
        'Ingredient',
        'Category',
        'Quantity Lost',
        'Unit',
        'Containers Equivalent',
      ],
      for (final r in records)
        [
          formatDateOnly(r.occurredAt),
          r.ingredientName,
          r.category.label,
          r.quantity,
          r.unitOfMeasure,
          // rounded, the raw division carries meaningless precision
          roundTo(r.containersEquivalent, 3),
        ],
    ];
  }

  /// the accuracy evidence, what the system expected against what was counted
  static List<List<Object?>> reconciliation(
    List<Map<String, Object?>> rows,
  ) {
    return [
      [
        'Shift',
        'Shift Closed',
        'Batch',
        'Ingredient',
        'Unit',
        'Expiry Date',
        'Theoretical Quantity',
        'Audited Quantity',
        'Variance',
        'Variance Type',
      ],
      for (final r in rows)
        [
          r['shift_id'],
          formatTimestamp(r['closed_at']),
          r['batch_id'],
          r['ingredient_name'],
          r['unit_of_measure'],
          r['expiry_date'],
          r['theoretical_quantity'],
          r['audited_quantity'],
          r['variance'],
          r['variance_type'],
        ],
    ];
  }

  /// the decision support evaluation, the scores and whether the item actually sold
  static List<List<Object?>> suggestions(List<Map<String, Object?>> rows) {
    return [
      [
        'Suggested At',
        'Shift',
        'Menu Item',
        'Batch',
        'Ingredient',
        'Expiry Risk Score',
        'Popularity Score',
        'Combined Score',
        'Accepted',
      ],
      for (final r in rows)
        [
          formatTimestamp(r['suggested_at']),
          r['shift_id'],
          r['menu_item_name'],
          r['batch_id'],
          r['ingredient_name'],
          r['expiry_risk_score'],
          r['popularity_score'],
          r['combined_score'],
          // yes/no reads better than 1/0 in a spreadsheet
          (r['was_accepted'] as int?) == 1 ? 'Yes' : 'No',
        ],
    ];
  }

  /// sales at the prices they actually sold for, not today's menu prices
  static List<List<Object?>> sales(List<Map<String, Object?>> rows) {
    return [
      [
        'Date',
        'Transaction',
        'Shift',
        'Cashier',
        'Menu Item',
        'Quantity',
        'Unit Price At Sale',
        'Line Total',
        'Voided',
      ],
      for (final r in rows)
        [
          formatTimestamp(r['transaction_datetime']),
          r['transaction_id'],
          r['shift_id'],
          r['cashier_name'],
          r['menu_item_name'],
          r['quantity'],
          r['unit_price_at_sale'],
          r['line_total'],
          (r['is_voided'] as int?) == 1 ? 'Yes' : 'No',
        ],
    ];
  }

  /// YYYY-MM-DD, no time, the loss chart works by day
  static String formatDateOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// YYYY-MM-DD HH:MM from a stored ISO-8601 string
  ///
  /// the stored values carry microseconds, which is noise in a report appendix,
  /// returns an empty cell for null rather than the text "null"
  static String formatTimestamp(Object? iso) {
    if (iso == null) return '';
    final text = iso.toString();
    final parsed = DateTime.tryParse(text);
    // leave anything unparseable exactly as stored rather than losing it
    if (parsed == null) return text;

    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  /// trims pointless decimals, e.g. 0.3333333333 to 0.333
  static double roundTo(double value, int places) {
    var factor = 1.0;
    for (var i = 0; i < places; i++) {
      factor *= 10;
    }
    return (value * factor).round() / factor;
  }
}
