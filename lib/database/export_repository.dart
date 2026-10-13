import 'database_helper.dart';

/// the raw joined rows each export needs
///
/// these return maps straight from sqlite rather than models, because an export is
/// a flat table and building objects just to flatten them again would be wasted work
class ExportRepository {
  ExportRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// every closing count, the accuracy evidence for the evaluation
  Future<List<Map<String, Object?>>> reconciliationRows({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _helper.database;
    return db.rawQuery('''
      SELECT r.shift_id, s.closed_at, r.batch_id,
             i.name AS ingredient_name, i.unit_of_measure,
             b.expiry_date,
             r.theoretical_quantity, r.audited_quantity, r.variance,
             r.variance_type
      FROM reconciliation_logs r
      JOIN shift_sessions s ON s.shift_id = r.shift_id
      JOIN inventory_batches b ON b.batch_id = r.batch_id
      JOIN ingredients i ON i.ingredient_id = b.ingredient_id
      WHERE COALESCE(s.closed_at, s.opened_at) >= ?
        AND COALESCE(s.closed_at, s.opened_at) <= ?
      ORDER BY s.shift_id, i.name COLLATE NOCASE
    ''', [from.toIso8601String(), to.toIso8601String()]);
  }

  /// every suggestion with its scores, for evaluating the decision support module
  Future<List<Map<String, Object?>>> suggestionRows({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _helper.database;
    return db.rawQuery('''
      SELECT sl.suggested_at, sl.shift_id, sl.batch_id,
             m.name AS menu_item_name,
             i.name AS ingredient_name,
             sl.expiry_risk_score, sl.popularity_score, sl.combined_score,
             sl.was_accepted
      FROM suggestion_logs sl
      JOIN menu_items m ON m.menu_item_id = sl.menu_item_id
      JOIN inventory_batches b ON b.batch_id = sl.batch_id
      JOIN ingredients i ON i.ingredient_id = b.ingredient_id
      WHERE sl.suggested_at >= ? AND sl.suggested_at <= ?
      ORDER BY sl.suggested_at
    ''', [from.toIso8601String(), to.toIso8601String()]);
  }

  /// one row per sold line, at the price it sold for
  Future<List<Map<String, Object?>>> salesRows({
    required DateTime from,
    required DateTime to,
  }) async {
    final db = await _helper.database;
    return db.rawQuery('''
      SELECT t.transaction_datetime, t.transaction_id, t.shift_id, t.is_voided,
             u.name AS cashier_name,
             m.name AS menu_item_name,
             ti.quantity, ti.unit_price_at_sale, ti.line_total
      FROM transaction_items ti
      JOIN transactions t ON t.transaction_id = ti.transaction_id
      JOIN shift_sessions s ON s.shift_id = t.shift_id
      JOIN users u ON u.user_id = s.user_id
      JOIN menu_items m ON m.menu_item_id = ti.menu_item_id
      WHERE t.transaction_datetime >= ? AND t.transaction_datetime <= ?
      ORDER BY t.transaction_datetime, t.transaction_id
    ''', [from.toIso8601String(), to.toIso8601String()]);
  }
}
