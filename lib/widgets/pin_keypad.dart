import 'package:flutter/material.dart';

/// 4 digit keypad with dots, shared by the pin entry and change pin screens
class PinKeypad extends StatefulWidget {
  const PinKeypad({
    super.key,
    required this.onCompleted,
    this.errorMessage,
  });

  /// called once 4 digits are in
  final void Function(String pin) onCompleted;

  /// shown in red under the dots when not null (e.g. "Incorrect PIN")
  final String? errorMessage;

  static const int pinLength = 4;

  @override
  State<PinKeypad> createState() => _PinKeypadState();
}

// stateful since it has to remember the digits typed so far between taps
class _PinKeypadState extends State<PinKeypad> {
  String _entered = '';

  void _addDigit(String digit) {
    if (_entered.length >= PinKeypad.pinLength) return;

    setState(() => _entered += digit);

    if (_entered.length == PinKeypad.pinLength) {
      final pin = _entered;
      // clear first so the dots are empty by the time the parent shows an error or navigates
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
        // reserve the line even with no error so the keypad doesn't jump when one appears
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
    // phone keypad layout, 1-9 then 0 with backspace on the right
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
            // circular, the way a phone keypad looks, the app's square corners
            // elsewhere would make these read as buttons in a form instead
            : FilledButton.tonal(
                onPressed: () => _addDigit(key),
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                ),
                child: Text(
                  key,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ),
    );
  }
}
