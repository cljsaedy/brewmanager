import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// shared look for the pin screens: one card in the middle of the screen,
// brown left half with the text, white right half with the pin pad or code box
class PinScreenFrame extends StatelessWidget {
  const PinScreenFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.right,
    this.stepLabel,
    this.error,
    this.actions = const [],
    this.showCancel = true,
  });

  // icon in the circle on the brown side
  final IconData icon;
  final String title;
  final String message;
  // what goes in the white right half
  final Widget right;
  // small label above the title, like "Step 1 of 2"
  final String? stepLabel;
  // red pill under the message, like "Wrong PIN"
  final String? error;
  // buttons under the message, like "Forgot PIN?"
  final List<Widget> actions;
  // false hides the back arrow (recovery code screen must not be skipped)
  final bool showCancel;

  // widest the card gets, so it doesnt stretch across the whole tablet
  static const double maxCardWidth = 760;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          // scrolls when the keyboard takes half the screen (forgot pin screen)
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxCardWidth),
              child: Card(
                // cut the brown half to the card's round corners
                clipBehavior: Clip.antiAlias,
                // IntrinsicHeight = both halves get the same height (the taller one)
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _brownSide(context)),
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: right),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // left half: app name, icon, step, title, message, error, buttons
  Widget _brownSide(BuildContext context) {
    return Container(
      color: AppColors.espresso,
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      // buttons on the brown side get caramel/cream colors so they show up on brown
      child: Theme(
        data: Theme.of(context).copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.caramel,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.cream,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top row: back arrow (if allowed) + app name
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  if (showCancel)
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      color: AppColors.cream,
                      tooltip: 'Cancel',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  if (showCancel) const SizedBox(width: 4),
                  const Text(
                    'BrewManager',
                    style: TextStyle(
                      color: AppColors.cream,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // icon in a see-through cream circle
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.cream.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.cream, size: 28),
            ),
            const SizedBox(height: 20),

            if (stepLabel != null) ...[
              Text(
                stepLabel!.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.caramel,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                color: AppColors.cream.withValues(alpha: 0.85),
                fontSize: 14,
                height: 1.4,
              ),
            ),

            if (error != null) ...[
              const SizedBox(height: 16),
              _ErrorPill(text: error!),
            ],
            if (actions.isNotEmpty) ...[const SizedBox(height: 20), ...actions],
          ],
        ),
      ),
    );
  }
}

// red rounded box with an icon, for "Wrong PIN" etc
class _ErrorPill extends StatelessWidget {
  const _ErrorPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.errorText, size: 18),
          const SizedBox(width: 8),
          // Flexible so long messages wrap instead of overflowing
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.errorText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
