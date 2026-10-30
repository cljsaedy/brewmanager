/// spacing and sizing, as a small set of values rather than ad-hoc numbers
///
/// the tablet is a samsung tab a7 lite, 1006 by 601 logical pixels in landscape,
/// which leaves about 545 once the app bar is taken off
///
/// that is tight, so touch target size and how much fits on screen pull against
/// each other, the app resolves it by screen rather than picking one answer:
/// the pos and the closing count get oversized targets because they are used fast
/// or one handed, the manager screens stay dense because they are used sitting down
class AppSpacing {
  AppSpacing._();

  /// inside a control, between an icon and its label
  static const double xs = 4;

  /// between tightly related things, lines of the same block
  static const double sm = 8;

  /// between a label and its control
  static const double md = 12;

  /// screen edges, and between unrelated rows
  ///
  /// 16 rather than 24 at the edges, the screen is only 1006 wide and the
  /// content needs that space more than the margin does
  static const double lg = 16;

  /// between sections of a screen
  static const double xl = 24;

  /// around a single centred thing, like the pin keypad
  static const double xxl = 32;
}

class AppSizes {
  AppSizes._();

  /// android's minimum comfortable target, used for secondary controls
  static const double minTarget = 48;

  /// list rows on the manager screens, dense but still tappable
  static const double rowHeight = 56;

  /// primary actions, checkout and submit count
  ///
  /// bigger than the material default because these are pressed in a hurry,
  /// standing up, sometimes with wet hands
  static const double actionHeight = 60;

  /// the plus and minus controls on the closing count and the loss dialog
  ///
  /// oversized on purpose, the barista is often holding a carton in the other hand
  static const double stepper = 64;

  /// shortest a pos tile may be, so the name and price stay readable at arm's length
  static const double posTileMin = 112;

  /// corner radius
  ///
  /// squarer than material 3's defaults, which are pill shaped and read as a
  /// consumer app, this reads as a tool
  static const double radius = 10;

  /// slightly larger radius for dialogs and cards
  static const double radiusLarge = 12;

  /// the coloured bar on expiry and variance rows, wide enough to read at a glance
  static const double statusBarWidth = 6;
}
