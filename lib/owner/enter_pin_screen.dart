import 'package:flutter/material.dart';

import '../data/owner_pin_store.dart';
import '../widgets/pin_pad.dart';
import 'forgot_pin_screen.dart';
import 'owner_section_screen.dart';
import 'pin_screen_frame.dart';

// asks for the owner pin before opening the owner section
class EnterPinScreen extends StatefulWidget {
  const EnterPinScreen({super.key, required this.store});

  final OwnerPinStore store;

  @override
  State<EnterPinScreen> createState() => _EnterPinScreenState();
}

class _EnterPinScreenState extends State<EnterPinScreen> {
  String? _error;
  // true while checking, stops taps from piling up
  bool _checking = false;

  Future<void> _onPinEntered(String pin) async {
    setState(() => _checking = true);
    final ok = await widget.store.checkPin(pin);
    if (!mounted) return;

    if (ok) {
      // swap to the owner section, so back from there goes straight to the barista side
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OwnerSectionScreen()),
      );
    } else {
      // no lockout, just let them try again
      setState(() {
        _checking = false;
        _error = 'Wrong PIN. Try again.';
      });
    }
  }

  void _forgotPin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ForgotPinScreen(store: widget.store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PinScreenFrame(
      icon: Icons.lock_outline,
      title: 'Owner PIN',
      message: 'Type the 4-digit owner PIN.',
      error: _error,
      actions: [
        TextButton(onPressed: _forgotPin, child: const Text('Forgot PIN?')),
      ],
      right: PinPad(onCompleted: _onPinEntered, enabled: !_checking),
    );
  }
}
