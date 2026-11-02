import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../data/stock_item_store.dart';
import '../layout/side_rail.dart';
import '../widgets/placeholder_tab.dart';
import 'stock_items/stock_items_tab.dart';

// owner side, only reachable through the pin
// "unlocked" is not saved anywhere: the owner is unlocked only while this screen is open,
// so leaving it in any way (lock button, back, home) means the pin is needed again
class OwnerSectionScreen extends StatefulWidget {
  const OwnerSectionScreen({super.key, required this.db});

  // the app's db (or the test db in tests), the owner tabs read and save through it
  final Database db;

  @override
  State<OwnerSectionScreen> createState() => _OwnerSectionScreenState();
}

class _OwnerSectionScreenState extends State<OwnerSectionScreen> {
  // the owner tabs in the rail, in order
  static const List<RailItem> _tabs = [
    RailItem(icon: Icons.insights_outlined, label: 'Analytics'),
    RailItem(icon: Icons.mail_outline, label: 'Reports'),
    RailItem(icon: Icons.restaurant_menu, label: 'Menu & Recipes'),
    RailItem(icon: Icons.inventory_2_outlined, label: 'Stock Items'),
    RailItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  // which owner tab is open, starts on 0 = Analytics
  int _selectedIndex = 0;

  // made once here so it isnt remade every time the screen redraws
  late final StockItemStore _stockStore = StockItemStore(widget.db);

  // listens for the app going to the background
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // onHide = app is no longer on screen (home button, switched apps), lock right away
    _lifecycle = AppLifecycleListener(onHide: _lock);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  // close everything on top of the barista side, that is the lock
  void _lock() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    // no barista top bar here, the rail has lock and exit at the bottom instead
    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SideRail(
              items: _tabs,
              subtitle: 'Owner',
              selectedIndex: _selectedIndex,
              onSelect: (index) => setState(() => _selectedIndex = index),
              bottomItem: const RailItem(
                icon: Icons.logout,
                label: 'Lock and exit',
              ),
              onBottomTap: _lock,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                // same as the barista side, keeps every tab alive and shows one
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    const PlaceholderTab(
                      title: 'Analytics',
                      note: 'The usage chart comes in Feature 10.',
                    ),
                    const PlaceholderTab(
                      title: 'Reports',
                      note: 'Sent reports come in Feature 10.',
                    ),
                    const PlaceholderTab(
                      title: 'Menu & Recipes',
                      note: 'Menu items, sizes and recipes come in Feature 3.',
                    ),
                    StockItemsTab(store: _stockStore),
                    const PlaceholderTab(
                      title: 'Settings',
                      note: 'Emails, keys, PIN and backup come in Feature 11.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
