import 'package:flutter/material.dart';

import '../logic/suggestion_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// the suggestion strip on the pos, shows the item WITH the reason
///
/// the framing is waste prevention, not up-selling, so the wording is about using
/// stock up rather than selling more
///
/// kept to one line, the tablet only has 545 pixels of height below the app bar
/// and every pixel this takes is a pixel off the menu grid
class SuggestionBanner extends StatelessWidget {
  const SuggestionBanner({
    super.key,
    required this.suggestion,
    required this.isColdStart,
    required this.onTap,
  });

  final Suggestion suggestion;

  /// true in the first week of deployment, when there is no sales history yet
  final bool isColdStart;

  /// adds the suggested item to the order, which also counts as accepting it
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final urgent = suggestion.isUrgent;

    // blue, not amber, red and amber and green all mean stock urgency elsewhere
    // and reusing one here would weaken what it means on the expiry matrix
    final background =
        urgent ? AppColors.infoSurface : AppColors.surfaceSunken;

    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                urgent ? Icons.lightbulb_outline : Icons.insights_outlined,
                size: 22,
                color: urgent ? AppColors.info : AppColors.inkMuted,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      urgent
                          ? 'Use up: ${suggestion.menuItem.name}'
                          : 'Suggested: ${suggestion.menuItem.name}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: urgent
                                ? AppColors.onInfoSurface
                                : AppColors.inkBody,
                          ),
                    ),
                    // the reason, which the spec requires shown with the item
                    Text(
                      isColdStart
                          ? '${suggestion.reason} '
                              'Ranked by expiry only so far.'
                          : suggestion.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: urgent
                            ? AppColors.onInfoSurface
                            : AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  // shorter than the app's standard action height, this is a
                  // convenience rather than the main way to add an item
                  minimumSize: const Size(0, AppSizes.minTarget),
                  backgroundColor: urgent ? AppColors.info : AppColors.ink,
                ),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
