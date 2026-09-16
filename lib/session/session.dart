import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../screens/pin_entry_screen.dart';

/// who is logged in app wide, set by the pin screen on login and cleared by logOut()
class Session {
  Session._();

  /// lets code with no BuildContext (the idle timer) reach the navigator, passed to MaterialApp in main.dart
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // later increments read this to stamp shifts and sales with who did them
  static AppUser? currentUser;

  static bool get isLoggedIn => currentUser != null;

  /// clears the session and goes back to the pin screen, used by both log out buttons and the idle lock
  static void logOut() {
    currentUser = null;
    // pushAndRemoveUntil drops every screen underneath so back can't reach anything that needed a login
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PinEntryScreen()),
      (_) => false,
    );
  }
}
