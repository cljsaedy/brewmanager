import 'package:flutter/material.dart';

/// every colour in the app, chosen one at a time
///
/// the rule this palette follows: the interface is nearly monochrome, and a
/// saturated colour only ever appears when it carries information
///
/// that rule exists because colour already has jobs in this system, the expiry
/// bands, variance direction, voided sales, so using colour decoratively as well
/// would dilute the meanings staff need to read at a glance
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------------
  // the neutral interface
  //
  // warm rather than blue-grey, a cafe counter in daylight, and it keeps the
  // semantic reds and greens looking deliberate against it
  // ---------------------------------------------------------------------------

  /// near black, used for primary buttons and headings
  static const Color ink = Color(0xFF2B2622);

  /// body text on light surfaces
  static const Color inkBody = Color(0xFF1C1A17);

  /// secondary text, meta lines, hints
  static const Color inkMuted = Color(0xFF6B6459);

  /// disabled text and controls
  static const Color inkDisabled = Color(0xFFA8A096);

  /// the page
  static const Color surface = Color(0xFFFAF8F5);

  /// cards and panels sitting on the page
  static const Color surfaceRaised = Color(0xFFFFFFFF);

  /// strips and filled rows that need to separate from the page without a border
  static const Color surfaceSunken = Color(0xFFEFEBE5);

  /// hairline dividers and card borders
  static const Color hairline = Color(0xFFDDD6CD);

  /// stronger borders, input outlines
  static const Color outline = Color(0xFF8C8378);

  // ---------------------------------------------------------------------------
  // semantic, these are the only saturated colours
  // ---------------------------------------------------------------------------

  /// expired or 48h or less, and also errors, one red keeps the palette small
  static const Color danger = Color(0xFFC62828);

  /// 7 days or less, and a surplus at the audit
  static const Color caution = Color(0xFFF9A825);

  /// more than 7 days, and a count that matched exactly
  static const Color safe = Color(0xFF2E7D32);

  /// the three bands again, darkened only enough to be legible as text
  ///
  /// amber on a pale surface is nearly unreadable at 13pt, so a shape filled with
  /// [caution] is paired with [cautionText] for any words or numbers on it,
  /// red and green are legible as they are and only exist here for consistency
  static const Color dangerText = danger;
  static const Color cautionText = Color(0xFF8A5000);
  static const Color safeText = safe;

  /// informational panels, the suggestion banner and the rotation break note
  ///
  /// blue because red, amber and green are all spoken for by stock urgency,
  /// reusing one of them here would weaken what it means on the expiry matrix
  static const Color info = Color(0xFF2F5D8A);

  /// background tint for those informational panels
  static const Color infoSurface = Color(0xFFDFE8F0);

  /// text on the info tint
  static const Color onInfoSurface = Color(0xFF1F3240);

  // ---------------------------------------------------------------------------
  // the loss chart
  // ---------------------------------------------------------------------------

  /// declared losses, a known incident, deliberately not a warning colour
  static const Color declaredLoss = info;

  /// unexplained drift, the thing the study is trying to reduce
  static const Color unexplainedLoss = danger;
}
