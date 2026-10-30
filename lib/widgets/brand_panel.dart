import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// the dark half of the lock and change-pin screens
///
/// these two are the only screens that aren't work, so they're the one place a
/// bold composition belongs, a near-black panel against the pale working surface
/// gives the app a front door without adding decoration to any screen staff
/// actually use during service
class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key, required this.caption});

  /// the line under the cafe name, says what this screen wants
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the wordmark carries the panel on its own, no logo
          Text(
            'BrewManager',
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.lg),
          // a hairline rule instead of a divider widget, it has to read on dark
          Container(width: 56, height: 2, color: Colors.white24),
          const SizedBox(height: AppSpacing.lg),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 19,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
