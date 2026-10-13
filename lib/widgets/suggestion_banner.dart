import 'package:flutter/material.dart';

import '../logic/suggestion_engine.dart';

/// the suggestion strip on the pos, shows the item WITH the reason
///
/// the framing is waste prevention, not up-selling, so the wording is about using
/// stock up rather than selling more
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
    final scheme = Theme.of(context).colorScheme;

    // only tint it when something is actually at risk, a green suggestion isn't urgent
    final background = suggestion.isUrgent
        ? scheme.tertiaryContainer
        : scheme.surfaceContainerHighest;

    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                suggestion.isUrgent
                    ? Icons.lightbulb_outline
                    : Icons.insights_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          suggestion.isUrgent
                              ? 'Use this up: ${suggestion.menuItem.name}'
                              : 'Suggested: ${suggestion.menuItem.name}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${suggestion.servingsPossible} can be made',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    // the reason, which the spec requires to be shown with the item
                    Text(suggestion.reason),
                    if (isColdStart)
                      Text(
                        'Ranked by expiry only — not enough sales history yet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
