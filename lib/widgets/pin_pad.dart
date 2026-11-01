import 'package:flutter/material.dart';

import '../security/pin_hasher.dart';
import '../theme/app_theme.dart';

// 4 dots on top + a number pad, calls onCompleted with the pin once 4 digits are tapped
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onCompleted, this.enabled = true});

  final ValueChanged<String> onCompleted;
  // false = taps do nothing, used while the pin is being checked/saved
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  // digits tapped so far
  String _entered = '';

  void _tapDigit(String digit) {
    if (!widget.enabled || _entered.length >= PinHasher.pinLength) return;

    final next = _entered + digit;
    if (next.length == PinHasher.pinLength) {
      // full pin, clear the dots for the next try and hand the pin to the screen
      setState(() => _entered = '');
      widget.onCompleted(next);
    } else {
      setState(() => _entered = next);
    }
  }

  void _backspace() {
    if (!widget.enabled || _entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // one dot per digit, filled brown once that digit is typed
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < PinHasher.pinLength; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _entered.length
                      ? AppColors.espresso
                      : Colors.transparent,
                  border: Border.all(color: AppColors.espresso, width: 1.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _keyRow(['1', '2', '3']),
        _keyRow(['4', '5', '6']),
        _keyRow(['7', '8', '9']),
        // last row: empty space, 0, backspace
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: _PadKey.width + 2 * _PadKey.gap),
            _PadKey(
              key: const Key('pin_key_0'),
              onTap: () => _tapDigit('0'),
              child: const Text('0'),
            ),
            _PadKey(
              key: const Key('pin_backspace'),
              onTap: _backspace,
              child: const Icon(Icons.backspace_outlined, size: 22),
            ),
          ],
        ),
      ],
    );
  }

  // one row of 3 digit keys
  Widget _keyRow(List<String> digits) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final digit in digits)
          _PadKey(
            key: Key('pin_key_$digit'),
            onTap: () => _tapDigit(digit),
            child: Text(digit),
          ),
      ],
    );
  }
}

// one big round-cornered key on the pad
class _PadKey extends StatelessWidget {
  const _PadKey({super.key, required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  // key size and space around each key, big enough for fingers
  static const double width = 76;
  static const double height = 54;
  static const double gap = 5;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(gap),
      child: Material(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Center(
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain,
                ),
                child: IconTheme(
                  data: const IconThemeData(color: AppColors.textMain),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
