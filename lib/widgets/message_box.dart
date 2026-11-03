import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// red error box or yellow notice box, used in the owner form panels
class MessageBox extends StatelessWidget {
  const MessageBox({super.key, required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final fg = isError ? AppColors.errorText : AppColors.warnText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorBg : AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
