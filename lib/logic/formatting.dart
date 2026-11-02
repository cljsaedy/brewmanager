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
