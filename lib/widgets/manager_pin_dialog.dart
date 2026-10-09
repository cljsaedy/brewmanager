import 'package:flutter/material.dart';

import '../database/user_repository.dart';
import '../models/app_user.dart';
import 'pin_keypad.dart';

/// asks for a manager pin and hands back the manager who entered it
///
/// a barista's own correct pin is rejected on purpose, this gates actions that
/// need manager approval like voiding a sale
/// returns the AppUser on success, null if cancelled
class ManagerPinDialog extends StatefulWidget {
  const ManagerPinDialog({super.key, required this.reason});

  /// shown above the keypad so it's clear what is being approved
  final String reason;

  /// convenience so callers don't repeat the showDialog boilerplate
  static Future<AppUser?> show(BuildContext context, String reason) {
    return showDialog<AppUser>(
      context: context,
      builder: (_) => ManagerPinDialog(reason: reason),
    );
  }

  @override
  State<ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends State<ManagerPinDialog> {
  final _users = UserRepository();
  String? _error;
  bool _checking = false;

  Future<void> _onPinEntered(String pin) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final user = await _users.findByPin(pin);
    if (!mounted) return;

    // wrong pin and a non-manager pin get the same message, so this can't be used to probe roles
    if (user == null || !user.isManager) {
      setState(() {
        _checking = false;
        _error = 'Not a valid Manager PIN';
      });
      return;
    }

    Navigator.pop(context, user);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manager approval'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.reason, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            PinKeypad(onCompleted: _onPinEntered, errorMessage: _error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
