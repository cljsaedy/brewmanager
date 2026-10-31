import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// the 3 looks a chip can have, ok = green, warn = amber, error = red
enum ChipTone { ok, warn, error }

// small rounded label like "Draft" or "Restock recommended"
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    // pick text color and background color based on the tone
    final Color textColor;
    final Color bgColor;
    switch (tone) {
      case ChipTone.ok:
        textColor = AppColors.okText;
        bgColor = AppColors.okBg;
      case ChipTone.warn:
        textColor = AppColors.warnText;
        bgColor = AppColors.warnBg;
      case ChipTone.error:
        textColor = AppColors.errorText;
        bgColor = AppColors.errorBg;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
