import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// shared look for the pin screens: text on the left, a card on the right (pin pad or code box)
class PinScreenFrame extends StatelessWidget {
  const PinScreenFrame({
    super.key,
    required this.title,
    required this.message,
    required this.right,
    this.error,
    this.actions = const [],
    this.showCancel = true,
  });

  final String title;
  final String message;
  // what goes in the right card
  final Widget right;
  // red text under the message, like "Wrong PIN"
  final String? error;
  // extra buttons under the message, like "Forgot PIN?"
  final List<Widget> actions;
  // false hides the cancel button (recovery code screen must not be skipped)
  final bool showCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCancel)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Cancel'),
                ),
              Expanded(
                child: Row(
                  children: [
                    // both sides can scroll, so nothing breaks when the keyboard takes half the screen
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: text.headlineSmall),
                            const SizedBox(height: 8),
                            Text(message, style: text.bodyMedium),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                error!,
                                style: const TextStyle(
                                  color: AppColors.errorText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            ...actions,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    SingleChildScrollView(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: right,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
