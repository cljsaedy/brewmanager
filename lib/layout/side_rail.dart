import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// one button in the rail, just an icon + a label
class RailItem {
  const RailItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

// the white panel on the left with the app name, the tabs, and one button at the bottom
// barista side: bottom button is the owner lock, owner side: bottom button is lock and exit
class SideRail extends StatelessWidget {
  const SideRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.bottomItem,
    required this.onBottomTap,
    this.subtitle,
  });

  final List<RailItem> items;
  // which tab is open right now (0 = first item)
  final int selectedIndex;
  // called with the tab number when a tab is tapped
  final ValueChanged<int> onSelect;
  // the button stuck at the bottom of the rail, and what happens when it is tapped
  final RailItem bottomItem;
  final VoidCallback onBottomTap;
  // small text under the app name, like 'Owner', null shows nothing
  final String? subtitle;

  // rail width, kept small since the tablet screen is narrow
  static const double width = 180;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // app name at the top, in place of the logo from the ui reference
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'BrewManager',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.espresso,
              ),
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.caramel,
                ),
              ),
            ),
          const SizedBox(height: 28),

          // one button per tab, loop with the index so we know which one is selected
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _RailButton(
                icon: items[i].icon,
                label: items[i].label,
                selected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
            ),

          // pushes the bottom button all the way down
          const Spacer(),
          const Divider(),
          const SizedBox(height: 8),
          _RailButton(
            icon: bottomItem.icon,
            label: bottomItem.label,
            selected: false,
            onTap: onBottomTap,
          ),
        ],
      ),
    );
  }
}

// the look of a single rail button, brown filled pill when selected
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // white on brown when selected, muted text when not
    final Color fg = selected ? Colors.white : AppColors.textMuted;

    // Material + InkWell gives the tap ripple effect inside the rounded shape
    return Material(
      color: selected ? AppColors.espresso : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              // Flexible lets the label shrink and end with "..." if the rail is too narrow
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
