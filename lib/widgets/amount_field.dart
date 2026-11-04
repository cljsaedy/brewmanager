import 'package:flutter/material.dart';

import '../logic/units.dart';

// number box with a unit picker on the right (or a fixed word like "bottles")
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.fieldKey,
    required this.unitKey,
    required this.label,
    required this.controller,
    required this.units,
    required this.unit,
    required this.onUnitChanged,
    this.fixedSuffix,
    this.onChanged,
  });

  final Key fieldKey;
  final Key unitKey;
  final String label;
  final TextEditingController controller;
  // units to pick from, the picker only shows when there is more than one
  final List<InputUnit> units;
  final InputUnit unit;
  final ValueChanged<InputUnit> onUnitChanged;
  // shown instead of the picker, like "bottles"
  final String? fixedSuffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    // the picker only makes sense with 2+ units (g/kg, ml/L/oz), pcs has just one
    final showPicker = fixedSuffix == null && units.length > 1;
    final suffix = fixedSuffix ?? (showPicker ? null : unit.label);

    return Row(
      children: [
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            onChanged: onChanged,
            // number keyboard with a dot for decimals
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: suffix),
          ),
        ),
        if (showPicker) ...[
          const SizedBox(width: 10),
          DropdownButton<InputUnit>(
            key: unitKey,
            value: unit,
            underline: const SizedBox.shrink(),
            items: [
              for (final option in units)
                DropdownMenuItem(value: option, child: Text(option.label)),
            ],
            onChanged: (picked) {
              if (picked != null) onUnitChanged(picked);
            },
          ),
        ],
      ],
    );
  }
}
