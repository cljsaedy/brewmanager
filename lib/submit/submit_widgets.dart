import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// the small building blocks of the submit screen, the steps and saving are in submit_screen.dart

// the 3 steps in order, the header draws one circle for each
const List<String> submitSteps = ['Review', 'Date', 'Done'];

// white card with round corners, same look as the top bar and the count table
class SubmitCard extends StatelessWidget {
  const SubmitCard({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

// bar on top of every step: title on the left, step tracker in the middle, buttons on the right
class SubmitHeader extends StatelessWidget {
  const SubmitHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.stepIndex,
    required this.actions,
  });

  final String title;
  // the small text under the title
  final String subtitle;
  // which step is open, 0 = the first one, null = no step tracker (the correct screen has no steps)
  final int? stepIndex;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SubmitCard(
      padding: 12,
      child: Row(
        children: [
          const SizedBox(width: 8),
          // Expanded so a long title ends with "..." and the buttons always fit
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (stepIndex != null) ...[
            _StepTracker(stepIndex: stepIndex!),
            const SizedBox(width: 20),
          ],
          for (final action in actions) ...[
            action,
            if (action != actions.last) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

// the Review - Date - Done circles
class _StepTracker extends StatelessWidget {
  const _StepTracker({required this.stepIndex});

  final int stepIndex;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    for (var i = 0; i < submitSteps.length; i++) {
      // the line between 2 steps
      if (i > 0) {
        parts.add(
          Container(
            width: 16,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: i <= stepIndex ? AppColors.okText : AppColors.divider,
          ),
        );
      }
      parts.add(_stepDot(i));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }

  Widget _stepDot(int index) {
    // the last step is done as soon as it opens, it has nothing left to do
    final isDone = index < stepIndex || stepIndex == submitSteps.length - 1;
    final isOpen = index == stepIndex;

    final Color circle;
    if (isDone) {
      circle = AppColors.okText;
    } else if (isOpen) {
      circle = AppColors.espresso;
    } else {
      circle = AppColors.divider;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
          child: isDone
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isOpen ? Colors.white : AppColors.textMuted,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          submitSteps[index],
          style: TextStyle(
            fontSize: 12,
            fontWeight: isOpen ? FontWeight.w700 : FontWeight.w500,
            color: isOpen || isDone ? AppColors.textMain : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// rounded square with an icon in it, the soft color makes the rows easy to scan
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    this.size = 34,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

// one number at the top of the review, like "Tally total 12"
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.espresso,
    this.background = AppColors.cream,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SubmitCard(
      padding: 12,
      child: Row(
        children: [
          IconTile(icon: icon, color: color, background: background),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// a card with a bold title and its own scrolling list
// it scrolls on its own so a long list never pushes the buttons away
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SubmitCard(
      padding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// one row of a list: icon, 2 lines of text, and something small on the right
class SubmitRow extends StatelessWidget {
  const SubmitRow({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    this.detail,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String? detail;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        // one line of text sits in the middle of its icon, 2 lines start at the top
        crossAxisAlignment: detail == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, background: background, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (detail != null) Text(detail!, style: text.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(trailing!, style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

// small muted line for an empty list, like "No notes"
class EmptyLine extends StatelessWidget {
  const EmptyLine(this.message, {super.key, this.icon = Icons.remove});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

// small caramel title inside a list, same look as the category titles in the count table
class ListTitle extends StatelessWidget {
  const ListTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.caramel,
        ),
      ),
    );
  }
}

// amber box for a warning on the date step, like the skipped day warning
class WarningBanner extends StatelessWidget {
  const WarningBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.warnText,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.warnText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// a date drawn like a calendar page: month band on top, big day, weekday under it
class CalendarTile extends StatelessWidget {
  const CalendarTile({
    super.key,
    required this.month,
    required this.day,
    required this.weekday,
  });

  final String month;
  final String day;
  final String weekday;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      // clip so the brown band follows the round corners
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.espresso,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              month.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            day,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 42,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: Text(
              weekday,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
