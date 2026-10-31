import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../widgets/status_chip.dart';

// bar on top of the barista screens: business date + status on the left, day note and submit on the right
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.businessDate,
    required this.isSubmitted,
    this.onDayNote,
    this.onSubmit,
  });

  // date of the count being worked on
  final DateTime businessDate;
  // false = Draft, true = Submitted
  final bool isSubmitted;
  // button actions, null makes the button greyed out (not built yet)
  final VoidCallback? onDayNote;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    // shows the date like "Sat, Oct 31"
    final dateText = DateFormat('EEE, MMM d').format(businessDate);

    return Container(
      height: 68,
      margin: const EdgeInsets.only(top: 12, right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Expanded takes all the free space so the buttons get pushed to the right side
          Expanded(
            child: Row(
              children: [
                // Flexible lets the date shrink and end with "..." so the buttons always fit
                Flexible(
                  child: Text(
                    dateText,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                StatusChip(
                  label: isSubmitted ? 'Submitted' : 'Draft',
                  tone: isSubmitted ? ChipTone.ok : ChipTone.warn,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onDayNote,
            icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
            label: const Text('Day Note'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
