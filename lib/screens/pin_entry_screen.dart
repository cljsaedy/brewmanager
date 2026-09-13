import 'package:flutter/material.dart';

import '../database/user_repository.dart';
import '../models/app_user.dart';
import '../session/session.dart';
import '../widgets/pin_keypad.dart';
import 'barista_home_screen.dart';
import 'manager_home_screen.dart';

/// The lock screen. Every session starts here.
///
/// On four digits it looks the PIN up, and if a user matches, replaces itself
/// with the home screen for that user's role. There is no username field:
/// the PIN alone identifies the person.
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
    // Ignore taps while a lookup is already running.
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final user = await _users.findByPin(pin);

    // The screen may have been disposed while we were waiting on the
    // database. Touching it after that is an error.
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

  /// Role detection and routing. pushReplacement removes this screen from
  /// the navigation stack so Back cannot return to it.
  void _goToHome(AppUser user) {
    Session.currentUser = user;

    final Widget home = user.isManager
        ? ManagerHomeScreen(user: user)
        : BaristaHomeScreen(user: user);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => home),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left half: branding and prompt.
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.coffee,
                    size: 96,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BrewManager',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Enter your PIN to begin'),
                ],
              ),
            ),
          ),
          // Right half: keypad.
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
