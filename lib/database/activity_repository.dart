import 'database_helper.dart';

/// finds the newest timestamp anywhere in the database, used by the clock check
class ActivityRepository {
  ActivityRepository({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  /// newest recorded event across every table that stamps a time, null on a fresh install
  Future<DateTime?> latestRecordedActivity() async {
    final db = await _helper.database;

    // all four are ISO-8601 text so MAX() compares them correctly as strings
    final rows = await db.rawQuery('''
      SELECT MAX(stamp) AS latest FROM (
        SELECT MAX(transaction_datetime) AS stamp FROM transactions
        UNION ALL
        SELECT MAX(received_at) FROM inventory_batches
        UNION ALL
        SELECT MAX(recorded_at) FROM loss_events
        UNION ALL
        SELECT MAX(opened_at) FROM shift_sessions
      )
    ''');

    final latest = rows.first['latest'] as String?;
    return latest == null ? null : DateTime.parse(latest);
  }
}
