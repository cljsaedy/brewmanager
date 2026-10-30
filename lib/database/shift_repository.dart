import '../models/shift.dart';
import 'database_helper.dart';

/// thrown when opening a shift while another one is still open
class ShiftAlreadyOpenException implements Exception {
  ShiftAlreadyOpenException(this.openShift);
  final Shift openShift;
}

/// db access for shift_sessions
class ShiftRepository {
  ShiftRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// the shift currently open, null when nobody has opened one
  Future<Shift?> getOpenShift() async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT s.*, u.name AS user_name
      FROM shift_sessions s
      JOIN users u ON u.user_id = s.user_id
      WHERE s.status = 'open'
      ORDER BY s.opened_at DESC
      LIMIT 1
    ''');
    return rows.isEmpty ? null : Shift.fromMap(rows.first);
  }

  /// opens a shift for this user, refuses when one is already open
  Future<int> openShift(int userId) async {
    final existing = await getOpenShift();
    if (existing != null) throw ShiftAlreadyOpenException(existing);

    final db = await _helper.database;
    return db.insert('shift_sessions', {
      'user_id': userId,
      'opened_at': DateTime.now().toIso8601String(),
      'closed_at': null,
      'status': 'open',
    });
  }

  /// stamps the close time and flips the status, the audit runs before this is called
  Future<void> closeShift(int shiftId) async {
    final db = await _helper.database;
    await db.update(
      'shift_sessions',
      {
        'closed_at': DateTime.now().toIso8601String(),
        'status': 'closed',
      },
      where: 'shift_id = ?',
      whereArgs: [shiftId],
    );
  }

  /// returns the open shift's id, opening one for this user if there isn't one
  ///
  /// the fallback is so a sale can never fail just because nobody pressed "open shift",
  /// the shift screen is the proper way to start one
  Future<int> getOrCreateOpenShift(int userId) async {
    final existing = await getOpenShift();
    if (existing != null) return existing.shiftId;

    final db = await _helper.database;
    return db.insert('shift_sessions', {
      'user_id': userId,
      'opened_at': DateTime.now().toIso8601String(),
      'closed_at': null,
      'status': 'open',
    });
  }

  /// newest shifts first, for the history list
  Future<List<Shift>> getRecent({int limit = 50}) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT s.*, u.name AS user_name
      FROM shift_sessions s
      JOIN users u ON u.user_id = s.user_id
      ORDER BY s.opened_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(Shift.fromMap).toList();
  }

  /// newest shifts first, each with what it took and whether it was counted
  Future<List<ShiftWithSummary>> getRecentWithSummary({int limit = 50}) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT s.*, u.name AS user_name,
             (SELECT COUNT(*) FROM transactions t
               WHERE t.shift_id = s.shift_id AND t.is_voided = 0)
               AS sale_count,
             -- voided sales are left out of the total, they were reversed
             (SELECT SUM(t.total_amount) FROM transactions t
               WHERE t.shift_id = s.shift_id AND t.is_voided = 0)
               AS sales_total,
             (SELECT COUNT(*) FROM transactions t
               WHERE t.shift_id = s.shift_id AND t.is_voided = 1)
               AS voided_count,
             (SELECT COUNT(*) FROM loss_events l
               WHERE l.shift_id = s.shift_id) AS loss_count,
             (SELECT COUNT(*) FROM reconciliation_logs r
               WHERE r.shift_id = s.shift_id) AS count_rows
      FROM shift_sessions s
      JOIN users u ON u.user_id = s.user_id
      ORDER BY s.opened_at DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(ShiftWithSummary.fromMap).toList();
  }

  /// what happened during one shift
  Future<ShiftSummary> getSummary(int shiftId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM transactions
          WHERE shift_id = ? AND is_voided = 0) AS sale_count,
        -- voided sales are left out of the total, they were reversed
        (SELECT SUM(total_amount) FROM transactions
          WHERE shift_id = ? AND is_voided = 0) AS sales_total,
        (SELECT COUNT(*) FROM transactions
          WHERE shift_id = ? AND is_voided = 1) AS voided_count,
        (SELECT COUNT(*) FROM loss_events
          WHERE shift_id = ?) AS loss_count
    ''', [shiftId, shiftId, shiftId, shiftId]);

    return ShiftSummary.fromMap(rows.first);
  }
}
