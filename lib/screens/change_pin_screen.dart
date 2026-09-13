import 'package:flutter/material.dart';

import '../database/user_repository.dart';
import '../models/app_user.dart';
import '../widgets/pin_keypad.dart';
import 'pin_entry_screen.dart';

/// Forces [user] to pick a new PIN. Shown on first launch, before anything
/// else is reachable, because the seeded Manager PIN is public knowledge.
///
/// Two phases: enter a new PIN, then enter it again to confirm. The default
/// PIN is rejected so the "change" cannot be a no-op.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _users = UserRepository();

  /// The PIN from phase one. Null means we are still in phase one.
  String? _firstEntry;
  String? _error;

  bool get _isConfirming => _firstEntry != null;

  Future<void> _onPinEntered(String pin) async {
    if (!_isConfirming) {
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

    if (pin != _firstEntry) {
      // Mismatch: start over from phase one.
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
