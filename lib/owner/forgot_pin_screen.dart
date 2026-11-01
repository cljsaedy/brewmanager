import 'package:flutter/material.dart';

import '../data/owner_pin_store.dart';
import 'create_pin_screen.dart';
import 'pin_screen_frame.dart';

// type the recovery code, if it is right the owner gets to make a new pin (no data lost)
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.store});

  final OwnerPinStore store;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  // holds the text typed in the box
  final _codeController = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    // controllers have to be cleaned up when the screen closes
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final ok = await widget.store.checkRecoveryCode(_codeController.text);
    if (!mounted) return;

    if (ok) {
      // right code, go make a new pin, that also makes a new recovery code so this one stops working
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CreatePinScreen(store: widget.store)),
      );
    } else {
      setState(() {
        _checking = false;
        _error = 'That code is not right. Check it and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PinScreenFrame(
      title: 'Forgot PIN',
      message:
          'Type the recovery code you saved when the PIN was made, '
          'like 7KQ2-M9XA.',
      error: _error,
      right: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeController,
              // shows the keyboard in caps, typing lowercase still works
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Recovery code'),
              onSubmitted: (_) => _check(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _checking ? null : _check,
              child: const Text('Check code'),
            ),
          ],
        ),
      ),
    );
  }
}
