import 'dart:async';

import 'package:flutter/material.dart';

import 'session.dart';

/// Locks the app after a period with no touches.
///
/// Wraps every screen (via MaterialApp.builder). A [Listener] sees each
/// pointer-down before the widgets underneath do, without consuming it, and
/// restarts the countdown. When the countdown fires and someone is logged
/// in, the session is ended and the PIN screen is shown.
class IdleLock extends StatefulWidget {
  const IdleLock({super.key, required this.child});

  final Widget child;

  /// How long the tablet can sit untouched before locking.
  static const Duration timeout = Duration(minutes: 2);

  @override
  State<IdleLock> createState() => _IdleLockState();
}

class _IdleLockState extends State<IdleLock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(IdleLock.timeout, _onIdle);
  }

  void _onIdle() {
    // Nothing to protect if no one is logged in (already on the PIN screen
    // or the first-launch change-PIN screen).
    if (Session.isLoggedIn) {
      Session.logOut();
    }
    // Keep counting so a later login is also protected.
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Translucent: we get notified of the touch AND it still reaches the
      // button underneath.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restartTimer(),
      child: widget.child,
    );
  }
}
