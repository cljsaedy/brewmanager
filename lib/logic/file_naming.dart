/// builds readable names for the files the app writes
///
/// the old names were stamps like suggestions_20261017_220527.csv, which are
/// unique and sortable but say nothing at a glance, and these files end up in a
/// folder being read weeks later while writing up the evaluation
///
/// pure dart, so the shape of a name can be unit tested without writing a file
library;

/// a file name for an export, saying what it holds and over what period
///
/// e.g. "Closing Counts (Last 30 days) 2026-10-17.csv"
///
/// the period is the user's own wording from the filter rather than a pair of
/// dates, because "Last 30 days" is what they picked and an all time export
/// would otherwise be named with a start date ten years in the past
String exportFileName({
  required String label,
  required String periodLabel,
  required String extension,
  required DateTime at,
}) {
  return '$label ($periodLabel) ${_date(at)}.$extension';
}

/// a file name for a backup
///
/// e.g. "Backup 2026-10-17 22-05.db", or "Before restore 2026-10-17 22-05.db"
///
/// the time is included because several can be taken in one day, and a colon is
/// not allowed in a file name so it is written with a hyphen
String backupFileName({required String label, required DateTime at}) {
  return '$label ${_date(at)} ${_time(at)}.db';
}

/// the same name with a counter added, used when the first choice already exists
///
/// e.g. "Sales (Last 7 days) 2026-10-17 (2).csv"
///
/// a readable name is not unique on its own, two exports of the same thing on
/// the same day would collide, and silently overwriting the first would lose it
String withCopyNumber(String fileName, int number) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '$fileName ($number)';

  final stem = fileName.substring(0, dot);
  final extension = fileName.substring(dot);
  return '$stem ($number)$extension';
}

String _date(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _time(DateTime d) => '${_two(d.hour)}-${_two(d.minute)}';

String _two(int n) => n.toString().padLeft(2, '0');
