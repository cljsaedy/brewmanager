/// how numbers are written on screen
///
/// the same little formatter had been copied into most screens, which is how two
/// screens end up disagreeing about whether to show 150 or 150.0
library;

/// peso amounts, no decimals when there are none to show
///
/// ₱150 rather than ₱150.00, because most cafe prices are whole and the extra
/// zeroes make a price list harder to scan
String money(double amount) {
  if (amount == amount.roundToDouble()) {
    return '₱${amount.toInt()}';
  }
  return '₱${amount.toStringAsFixed(2)}';
}

/// quantities of an ingredient, trailing zeroes dropped
///
/// 30 not 30.0, but 7.5 stays 7.5
///
/// rounded to two places first, because a value that came out of a division
/// carries floating point noise and would otherwise print as 3.03599999999999
String quantity(double value) {
  final rounded = (value * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) {
    return rounded.toInt().toString();
  }
  return rounded.toString();
}
