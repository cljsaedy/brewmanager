import 'package:flutter/material.dart';

import '../data/owner_pin_store.dart';
import '../widgets/pin_pad.dart';
import 'pin_screen_frame.dart';
import 'recovery_code_screen.dart';

// type a new pin, then type it again to confirm, then show the new recovery code
// used for the first pin, after "forgot pin", change pin in settings, and the setup wizard
class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({
    super.key,
    required this.store,
    this.onCodeSaved,
    this.showCancel = true,
    this.title = 'Create owner PIN',
  });

  final OwnerPinStore store;
  // what "I saved it" on the recovery code screen does, it gets the plain code too
  // null = open the owner section, see RecoveryCodeScreen
  final void Function(BuildContext context, String code)? onCodeSaved;
  // false in the setup wizard, there is nothing to go back to
  final bool showCancel;
  // the title of step 1, like "Create owner PIN" or "New owner PIN"
  final String title;

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  // the first pin typed, null while still on the first step
  String? _firstPin;
  String? _error;
  // true while saving, stops a double save
  bool _saving = false;

  Future<void> _onPinEntered(String pin) async {
    // step 1, remember it and ask again
    if (_firstPin == null) {
      setState(() {
        _firstPin = pin;
        _error = null;
      });
      return;
    }

    // step 2, both have to match, if not start over from step 1
    if (pin != _firstPin) {
      setState(() {
        _firstPin = null;
        _error = "The PINs didn't match. Start again.";
      });
      return;
    }

    setState(() => _saving = true);
    final code = await widget.store.setPin(pin);

    // mounted = this screen is still open (the owner could have left while saving)
    if (!mounted) return;
    // pushReplacement = swap this screen for the next one, so back doesnt return here
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RecoveryCodeScreen(
          code: code,
          db: widget.store.db,
          onSaved: widget.onCodeSaved == null
              ? null
              : (context) => widget.onCodeSaved!(context, code),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _firstPin != null;

    return PinScreenFrame(
      icon: Icons.lock_outline,
      stepLabel: confirming ? 'Step 2 of 2' : 'Step 1 of 2',
      title: confirming ? 'Confirm owner PIN' : widget.title,
      message: confirming
          ? 'Type the same 4 digits again.'
          : 'Pick 4 digits. You need this PIN to open the owner section.',
      error: _error,
      showCancel: widget.showCancel,
      right: PinPad(onCompleted: _onPinEntered, enabled: !_saving),
    );
  }
}
