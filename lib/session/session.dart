import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../screens/pin_entry_screen.dart';

/// Who is currently logged in, app-wide.
///
/// Set by the PIN screen on a successful login, cleared by [logOut]. Later
/// increments read [currentUser] to stamp shifts and transactions with the
/// user who performed them.
class Session {
  Session._();

  /// Lets code with no BuildContext (the idle timer) reach the navigator.
  /// Passed to MaterialApp in main.dart.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static AppUser? currentUser;

  static bool get isLoggedIn => currentUser != null;

  /// Clears the session and returns to the PIN screen.
  ///
  /// pushAndRemoveUntil puts the PIN screen up and discards every screen
  /// beneath it, so Back cannot reach anything that needed a login. Used by
  /// both the Log Out buttons and the idle lock so both take the same path.
  static void logOut() {
    currentUser = null;
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PinEntryScreen()),
      (_) => false,
    );
  }
}
