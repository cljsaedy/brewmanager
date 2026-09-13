import 'package:flutter/material.dart';

/// A 4-digit numeric keypad with dot indicators.
///
/// Used by both the PIN entry screen and the change-PIN screen. It is a
/// StatefulWidget because it must remember the digits typed so far between
/// taps. When the fourth digit is entered, [onCompleted] fires with the PIN
/// and the keypad clears itself.
class PinKeypad extends StatefulWidget {
  const PinKeypad({
    super.key,
    required this.onCompleted,
    this.errorMessage,
  });

  /// Called once four digits have been entered.
  final void Function(String pin) onCompleted;

  /// Shown in red under the dots when non-null (e.g. "Incorrect PIN").
  final String? errorMessage;

  static const int pinLength = 4;

  @override
  State<PinKeypad> createState() => _PinKeypadState();
}

class _PinKeypadState extends State<PinKeypad> {
  String _entered = '';

  void _addDigit(String digit) {
    if (_entered.length >= PinKeypad.pinLength) return;

    setState(() => _entered += digit);

    if (_entered.length == PinKeypad.pinLength) {
      final pin = _entered;
      // Clear before reporting, so the dots are empty by the time the
      // parent screen reacts (e.g. shows an error or navigates away).
      setState(() => _entered = '');
      widget.onCompleted(pin);
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDots(context),
        const SizedBox(height: 8),
        // Reserve the line even when there is no error, so the keypad
        // does not jump down when a message appears.
        SizedBox(
          height: 24,
          child: Text(
            widget.errorMessage ?? '',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        const SizedBox(height: 16),
        _buildKeys(),
      ],
    );
  }

  Widget _buildDots(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(PinKeypad.pinLength, (index) {
        final filled = index < _entered.length;
        return Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
        );
      }),
    );
  }

  Widget _buildKeys() {
    // Laid out like a phone keypad: 1-9 in three rows, then 0 with a
    // backspace to its right.
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '<'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final key in row) _buildKey(key)],
          ),
      ],
    );
  }

  Widget _buildKey(String key) {
    const size = 80.0;

    if (key.isEmpty) {
      return const SizedBox(width: size, height: size);
    }

    final isBackspace = key == '<';

    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: size - 12,
        height: size - 12,
        child: isBackspace
            ? IconButton(
                onPressed: _backspace,
                icon: const Icon(Icons.backspace_outlined, size: 28),
              )
            : FilledButton.tonal(
                onPressed: () => _addDigit(key),
                child: Text(key, style: const TextStyle(fontSize: 28)),
              ),
      ),
    );
  }
}
