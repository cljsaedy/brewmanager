import 'package:flutter/material.dart';

import 'side_rail.dart';
import 'top_bar.dart';

// the main frame of the barista side: rail on the left, top bar on top, selected tab below it
class AppLayout extends StatefulWidget {
  const AppLayout({super.key});

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  // the barista tabs in the rail, in order
  static const List<RailItem> _tabs = [
    RailItem(icon: Icons.inventory_2_outlined, label: 'Count'),
    RailItem(icon: Icons.receipt_long_outlined, label: 'Tally'),
    RailItem(icon: Icons.history, label: 'History'),
  ];

  // which tab is open, starts on 0 = Count since that is the default tab
  int _selectedIndex = 0;

  void _selectTab(int index) {
    // setState tells flutter to redraw the screen with the new tab
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openOwner() {
    // placeholder until the pin screen is built in step 1d
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Owner section comes in step 1d')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SideRail(
              items: _tabs,
              selectedIndex: _selectedIndex,
              onSelect: _selectTab,
              onOwnerTap: _openOwner,
            ),
            // Expanded = take up all the space left of the rail
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // placeholder date is today, real business date comes in feature 4
                  // buttons have no action yet so they show greyed out until feature 7
                  TopBar(businessDate: DateTime.now(), isSubmitted: false),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      // IndexedStack keeps all tabs alive but only shows the selected one,
                      // so switching tabs doesnt lose what was on them
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: const [
                          _PlaceholderTab(
                            title: 'Count tab',
                            note: 'The logbook table comes in Feature 4.',
                          ),
                          _PlaceholderTab(
                            title: 'Tally tab',
                            note: 'The menu grid comes in Feature 5.',
                          ),
                          _PlaceholderTab(
                            title: 'History tab',
                            note: 'Submitted days come in Feature 8.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// temporary empty card for tabs that are not built yet
class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(note, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
