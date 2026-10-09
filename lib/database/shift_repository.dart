import 'database_helper.dart';

/// db access for shift_sessions
///
/// only the bare minimum for now, a sale needs a shift_id because transactions.shift_id
/// is NOT NULL, increment 4 adds the real open/close screen and the closing audit
class ShiftRepository {
  ShiftRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// returns the open shift's id, opening one for this user if there isn't one
  Future<int> getOrCreateOpenShift(int userId) async {
    final db = await _helper.database;

    final rows = await db.query(
      'shift_sessions',
      columns: ['shift_id'],
      where: 'status = ?',
      whereArgs: ['open'],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['shift_id'] as int;

    return db.insert('shift_sessions', {
      'user_id': userId,
      'opened_at': DateTime.now().toIso8601String(),
      'closed_at': null,
      'status': 'open',
    });
  }
}
