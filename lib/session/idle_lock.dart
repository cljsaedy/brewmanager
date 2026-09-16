import 'dart:async';

import 'package:flutter/material.dart';

import 'session.dart';

/// locks the app after a while with no touches, wraps every screen via MaterialApp.builder
class IdleLock extends StatefulWidget {
  const IdleLock({super.key, required this.child});

  final Widget child;

  /// how long the tablet can sit untouched before locking
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
    // nothing to protect if no one is logged in (already on pin or change pin screen)
    if (Session.isLoggedIn) {
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
