import 'package:intl/intl.dart';

// numbers for screens and emails: commas for thousands, at most 2 decimals, no ".0" at the end
// like 2000 -> "2,000", 2.5 -> "2.5", 0.333 -> "0.33"
final NumberFormat _amountFormat = NumberFormat('#,##0.##');

String formatAmount(double value) => _amountFormat.format(value);

// an amount with its unit, like "2,000 ml"
String formatWithUnit(double value, String unit) =>
    '${formatAmount(value)} $unit';

// a number of containers with the label made plural when it isnt exactly 1
// like (1, 'bottle') -> "1 bottle", (2.5, 'bottle') -> "2.5 bottles", (2, 'box') -> "2 boxes"
String formatContainers(double count, String label) {
  return '${formatAmount(count)} ${count == 1 ? label : pluralOf(label)}';
}

// simple english plural, good enough for container names
// words ending in s, x, ch or sh get "es" (box -> boxes), the rest get "s" (bottle -> bottles)
String pluralOf(String word) {
  final lower = word.toLowerCase();
  if (lower.endsWith('s') ||
      lower.endsWith('x') ||
      lower.endsWith('ch') ||
      lower.endsWith('sh')) {
    return '${word}es';
  }
  return '${word}s';
}

// first letter big, like "bottle" -> "Bottle"
String capitalized(String word) {
  if (word.isEmpty) return word;
  return '${word[0].toUpperCase()}${word.substring(1)}';
}

// a time on the tablet's clock, small letters, like "2:15pm"
final DateFormat _timeFormat = DateFormat('h:mma');

String formatTime(DateTime time) => _timeFormat.format(time).toLowerCase();

// number for a text box without commas or rounding, so saving again doesnt change it
// like 2000.0 -> "2000", 29.5735 -> "29.5735"
String plainNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

// reads a typed number, commas allowed ("2,000"), null if it isnt a number
double? readNumber(String text) {
  return double.tryParse(text.trim().replaceAll(',', ''));
}

// a YYYY-MM-DD date with its weekday, like "Fri, Oct 30"
String formatLongDate(String date) {
  return DateFormat('EEE, MMM d').format(DateTime.parse(date));
}

// a YYYY-MM-DD date without its weekday, like "Oct 30"
String formatShortDate(String date) {
  return DateFormat('MMM d').format(DateTime.parse(date));
}

// the dates a count covers, like "Oct 29–30" or "Oct 31–Nov 2" over the end of a month
String formatCovers(String from, String to) {
  final sameMonth = from.substring(0, 7) == to.substring(0, 7);
  final end = sameMonth
      ? DateFormat('d').format(DateTime.parse(to))
      : formatShortDate(to);
  return '${formatShortDate(from)}–$end';
}
