import '../models/sale.dart';
import 'database_helper.dart';

/// read access to recorded sales, for the history list and receipt reprints
class TransactionRepository {
  TransactionRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// newest sales first, voided ones included so they can be seen as voided
  Future<List<Sale>> getRecent({int limit = 100}) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT t.*,
             (SELECT SUM(ti.quantity) FROM transaction_items ti
               WHERE ti.transaction_id = t.transaction_id) AS item_count,
             u.name AS cashier_name
      FROM transactions t
      JOIN shift_sessions s ON s.shift_id = t.shift_id
      JOIN users u ON u.user_id = s.user_id
      ORDER BY t.transaction_datetime DESC, t.transaction_id DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(Sale.fromMap).toList();
  }

  /// the lines of one sale, priced at what they sold for not today's menu price
  Future<List<SaleItem>> getItems(int transactionId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT ti.quantity, ti.unit_price_at_sale, ti.line_total,
             m.name AS menu_item_name
      FROM transaction_items ti
      JOIN menu_items m ON m.menu_item_id = ti.menu_item_id
      WHERE ti.transaction_id = ?
      ORDER BY m.name COLLATE NOCASE
    ''', [transactionId]);
    return rows.map(SaleItem.fromMap).toList();
  }
}
