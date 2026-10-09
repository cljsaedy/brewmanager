/// spots the tablet's clock having moved backwards
///
/// every recorded event has a timestamp, so the newest one in the database is a floor
/// on what "now" can be, you can't have recorded a sale in the future
/// if the device says it's earlier than that, the clock was changed or reset
///
/// this does not need a settings table, and it survives reinstalling the app on the same database
/// the limit is that it only catches movement back past the last recorded activity,
/// a small drift on a quiet morning won't show up, which is fine for what this guards against
library;

/// the gap found, null is returned instead when the clock looks sane
class ClockWarning {
  final DateTime deviceNow;
  final DateTime latestRecorded;

  const ClockWarning({required this.deviceNow, required this.latestRecorded});

  /// how far back the clock appears to have gone
  Duration get drift => latestRecorded.difference(deviceNow);

  /// rounded up, a 90 minute gap reads as 1 day rather than 0
  int get driftDays => drift.inDays;

  String get summary {
    final d = drift;
    if (d.inDays >= 1) {
      return '${d.inDays} day${d.inDays == 1 ? '' : 's'}';
    }
    if (d.inHours >= 1) {
      return '${d.inHours} hour${d.inHours == 1 ? '' : 's'}';
    }
    return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'}';
  }
}

class ClockGuard {
  ClockGuard._();

  /// small gaps are ignored, clocks drift by seconds all the time and that's harmless
  static const Duration tolerance = Duration(minutes: 5);

  /// [latestRecorded] is the newest timestamp in the database, null on a fresh install
  static ClockWarning? check(DateTime deviceNow, DateTime? latestRecorded) {
    // nothing recorded yet means nothing to compare against
    if (latestRecorded == null) return null;

    // device time is at or after the last event, which is normal
    if (!deviceNow.isBefore(latestRecorded)) return null;

    // behind, but within tolerance, so not worth alarming anyone
    if (latestRecorded.difference(deviceNow) <= tolerance) return null;

    return ClockWarning(deviceNow: deviceNow, latestRecorded: latestRecorded);
  }
}
