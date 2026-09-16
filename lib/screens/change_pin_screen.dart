import 'package:flutter/material.dart';

import '../database/user_repository.dart';
import '../models/app_user.dart';
import '../widgets/pin_keypad.dart';
import 'pin_entry_screen.dart';

/// forces the user to pick a new pin, shown on first launch since the seeded pin is public knowledge
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

// two phases, enter new pin then enter it again to confirm
class _ChangePinScreenState extends State<ChangePinScreen> {
  final _users = UserRepository();

  /// pin from phase one, null means still in phase one
  String? _firstEntry;
  String? _error;

  bool get _isConfirming => _firstEntry != null;

  Future<void> _onPinEntered(String pin) async {
    if (!_isConfirming) {
      // reject the default so the "change" can't be a no-op
      if (pin == UserRepository.defaultManagerPin) {
        setState(() => _error = 'Please choose a PIN other than the default');
        return;
      }
      setState(() {
        _firstEntry = pin;
        _error = null;
      });
      return;
    }

    // mismatch, start over from phase one
    if (pin != _firstEntry) {
      setState(() {
        _firstEntry = null;
        _error = 'PINs did not match — try again';
      });
      return;
    }

    await _users.updatePin(widget.user.userId, pin);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PinEntryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_reset,
                      size: 96,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Set a new Manager PIN',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'The default PIN must be replaced before '
                      'BrewManager can be used.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isConfirming ? 'Confirm new PIN' : 'Enter new PIN',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  PinKeypad(
                    onCompleted: _onPinEntered,
                    errorMessage: _error,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
