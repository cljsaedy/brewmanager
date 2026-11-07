import 'package:intl/intl.dart';

// the date rules of a business day (rule 5), no db and no screens here so it is easy to test
// dates are YYYY-MM-DD text like everywhere in the db

final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

// utc here so daylight saving can never make a day 23 hours long and throw off the count
DateTime _parse(String date) {
  final local = _dateFormat.parse(date);
  return DateTime.utc(local.year, local.month, local.day);
}

// a DateTime as date text, the part the tablet shows on its calendar
String dateText(DateTime time) => _dateFormat.format(time);

// the date some days later, day + n in the constructor handles the end of a month, Oct 31 -> Nov 1
String addDays(String date, int days) {
  final start = _parse(date);
  return dateText(DateTime.utc(start.year, start.month, start.day + days));
}

// how many days from one date to another, negative if "to" comes first
int daysBetween(String from, String to) {
  return _parse(to).difference(_parse(from)).inDays;
}

// true when a day can be submitted with this date
// it can stay or move forward but never go back (rule 5)
// the draft is always after the last submitted day, so forward can never repeat a submitted date
bool canSubmitOn({required String draftDate, required String chosenDate}) {
  return daysBetween(draftDate, chosenDate) >= 0;
}

// the warning for a draft more than 1 day behind the tablet, null when there is nothing to warn about
// 1 day behind is normal, like still counting yesterday after midnight
String? skippedDayWarning({required String draftDate, required String today}) {
  final days = daysBetween(draftDate, today);
  if (days <= 1) return null;
  return 'This is $days days ago. Did you skip a day?';
}

// the dates passed over when the barista moves the date forward
// the draft's own date counts since nothing gets submitted on it anymore, the chosen date doesnt
// like draft Oct 28 moved to Oct 30 = Oct 28 and Oct 29
List<String> skippedDates({
  required String draftDate,
  required String chosenDate,
}) {
  final days = daysBetween(draftDate, chosenDate);
  return [for (var i = 0; i < days; i++) addDays(draftDate, i)];
}
