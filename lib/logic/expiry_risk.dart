/// expiry risk for a batch, worked out from the device date
///
/// pure dart so it can be unit tested, and increment 4's suggestion scoring reuses it
/// (score = 0.6 × highest expiry risk among ingredients + 0.4 × popularity)
library;

/// the three colour bands, score is the number the suggestion maths uses
enum ExpiryBand {
  red(1.0), // expired, or 48h or less left
  yellow(0.5), // 7 days or less
  green(0.0); // more than 7 days

  const ExpiryBand(this.score);

  final double score;
}

class ExpiryRisk {
  ExpiryRisk._();

  /// [expiryDate] is YYYY-MM-DD, [today] is passed in so tests don't depend on the real clock
  static ExpiryBand bandFor(String expiryDate, DateTime today) {
    final days = daysUntil(expiryDate, today);

    // 2 days or fewer covers expired, today, tomorrow and the day after (the 48h band)
    if (days <= 2) return ExpiryBand.red;
    if (days <= 7) return ExpiryBand.yellow;
    return ExpiryBand.green;
  }

  /// whole days from today to the expiry date, negative when already past
  static int daysUntil(String expiryDate, DateTime today) {
    final expiry = DateTime.parse(expiryDate);
    // drop the time of day on both sides, otherwise a batch expiring today
    // would change band depending on what time the screen is opened
    final startOfToday = DateTime(today.year, today.month, today.day);
    return expiry.difference(startOfToday).inDays;
  }

  static bool isExpired(String expiryDate, DateTime today) =>
      daysUntil(expiryDate, today) < 0;

  /// wording for the matrix, e.g. "expires in 3 days" or "expired 2 days ago"
  static String describe(String expiryDate, DateTime today) {
    final days = daysUntil(expiryDate, today);
    if (days < 0) {
      final ago = -days;
      return 'expired $ago day${ago == 1 ? '' : 's'} ago';
    }
    if (days == 0) return 'expires today';
    if (days == 1) return 'expires tomorrow';
    return 'expires in $days days';
  }
}
