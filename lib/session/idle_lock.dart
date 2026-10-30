import 'dart:async';

import 'package:flutter/material.dart';

import 'session.dart';

/// locks the app after a while with no touches, wraps every screen via MaterialApp.builder
class IdleLock extends StatefulWidget {
  const IdleLock({super.key, required this.child});

  final Widget child;

  /// how long the tablet can sit untouched before locking
  static const Duration timeout = Duration(minutes: 2);

  /// how many screens have asked not to be locked out
  ///
  /// a counter rather than a flag so nested suspends can't leave it stuck on
  static int _suspendCount = 0;

  static bool get isSuspended => _suspendCount > 0;

  /// stops the idle lock while a screen is open
  ///
  /// the closing count is the one place this is right, the barista is standing
  /// at the fridge counting and not touching the tablet for minutes at a time,
  /// and being thrown back to the pin screen loses a half finished count of the
  /// physical shelf, which is worse than the screen staying up
  ///
  /// it is also the screen with the least to protect, the whole point of the
  /// blind audit is that it shows no figures
  ///
  /// every call must be paired with [resume], do it in initState and dispose
  static void suspend() => _suspendCount++;

  static void resume() {
    if (_suspendCount > 0) _suspendCount--;
  }

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
    // nothing to protect if no one is logged in (already on pin or change pin screen)
    // and a screen may have asked to be left alone, see IdleLock.suspend
    if (Session.isLoggedIn && !IdleLock.isSuspended) {
      Session.logOut();
    }
    // keep counting so a later login is also protected
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    // Listener sees every touch before the widget underneath does, translucent means the touch still reaches the button
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restartTimer(),
      child: widget.child,
    );
  }
}
