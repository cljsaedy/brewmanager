import 'package:flutter/material.dart';

import '../database/user_repository.dart';
import '../models/app_user.dart';
import '../session/session.dart';
import '../widgets/brand_panel.dart';
import '../widgets/pin_keypad.dart';
import 'barista_home_screen.dart';
import 'manager_home_screen.dart';

/// lock screen, every session starts here, no username since the pin alone identifies the person
class PinEntryScreen extends StatefulWidget {
  const PinEntryScreen({super.key});

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final _users = UserRepository();
  String? _error;
  bool _checking = false;

  Future<void> _onPinEntered(String pin) async {
    // ignore taps while a lookup is already running
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final user = await _users.findByPin(pin);

    // screen might be gone by the time the db answers, touching it after that crashes
    if (!mounted) return;

    if (user == null) {
      setState(() {
        _checking = false;
        _error = 'Incorrect PIN';
      });
      return;
    }

    _goToHome(user);
  }

  /// role detection and routing
  void _goToHome(AppUser user) {
    Session.currentUser = user;

    final Widget home = user.isManager
        ? ManagerHomeScreen(user: user)
        : BaristaHomeScreen(user: user);

    // pushReplacement removes this screen from the stack so back can't return to it
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => home),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // left half, the dark brand panel
          const Expanded(
            child: BrandPanel(
              caption: 'Enter your PIN to start serving.',
            ),
          ),
          // right half, keypad on the pale working surface
          Expanded(
            child: Center(
              child: PinKeypad(
                onCompleted: _onPinEntered,
                errorMessage: _error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
