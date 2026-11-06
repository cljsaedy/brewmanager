import 'package:flutter/material.dart';

import '../count/count_tab.dart';
import '../data/count_line.dart';
import '../data/count_store.dart';
import '../data/database_helper.dart';
import '../data/owner_pin_store.dart';
import '../owner/create_pin_screen.dart';
import '../owner/enter_pin_screen.dart';
import '../widgets/placeholder_tab.dart';
import 'side_rail.dart';
import 'top_bar.dart';

// tells a screen when the screens on top of it have closed, MaterialApp needs this in navigatorObservers
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

// the main frame of the barista side: rail on the left, top bar on top, selected tab below it
class AppLayout extends StatefulWidget {
  const AppLayout({
    super.key,
    this.openPinStore = _realPinStore,
    this.openCountStore = _realCountStore,
  });

  // gives the pin store when the owner lock is tapped
  // the app uses the real database, tests pass their own test database here
  final Future<OwnerPinStore> Function() openPinStore;

  // gives the count store, same idea as openPinStore
  final Future<CountStore> Function() openCountStore;

  static Future<OwnerPinStore> _realPinStore() async {
    return OwnerPinStore(await DatabaseHelper.database);
  }

  static Future<CountStore> _realCountStore() async {
    return CountStore(await DatabaseHelper.database);
  }

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

// RouteAware = flutter calls didPopNext below when this screen shows again
class _AppLayoutState extends State<AppLayout> with RouteAware {
  // the barista tabs in the rail, in order
  static const List<RailItem> _tabs = [
    RailItem(icon: Icons.inventory_2_outlined, label: 'Count'),
    RailItem(icon: Icons.receipt_long_outlined, label: 'Tally'),
    RailItem(icon: Icons.history, label: 'History'),
  ];

  // which tab is open, starts on 0 = Count since that is the default tab
  int _selectedIndex = 0;

  // the day being counted, null while still loading from the db
  // kept here and not in the count tab since the top bar needs its date too
  DraftDay? _draft;
  // null until the first load, the count tab saves through this
  CountStore? _countStore;
  // goes up when the owner section closes, the new key makes the count tab start fresh
  // so an open panel never shows an item the owner just changed
  int _countTabVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  // ModalRoute.of needs context, so this cant go in initState
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  // the screen on top closed, back here from the owner section or the pin screen
  // IndexedStack keeps this tab alive so it wont read the db by itself, the owner could have changed stock items
  // this cant be done after the await in _openOwner, the pin screen swaps itself for the owner section
  // so that await ends when the pin is right, not when the owner leaves
  @override
  void didPopNext() {
    setState(() => _countTabVersion++);
    _loadDraft();
  }

  // gets the draft day ready and reads it, then redraws
  Future<void> _loadDraft() async {
    final store = await widget.openCountStore();
    final draft = await store.loadDraft();
    // mounted = this screen is still open
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _countStore = store;
    });
  }

  void _selectTab(int index) {
    // setState tells flutter to redraw the screen with the new tab
    setState(() {
      _selectedIndex = index;
    });
  }

  // true while the owner screen is being opened, stops a double tap opening it twice
  bool _openingOwner = false;

  // owner lock tapped: make a pin if there is none yet, otherwise ask for it
  Future<void> _openOwner() async {
    if (_openingOwner) return;
    _openingOwner = true;

    // try/finally = the flag always gets reset, even if opening fails with an error
    try {
      final store = await widget.openPinStore();
      final hasPin = await store.hasPin();
      if (!mounted) return;

      // await waits until that pin screen closes, so the flag stays on while it is open
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => hasPin
              ? EnterPinScreen(store: store)
              : CreatePinScreen(store: store),
        ),
      );
    } finally {
      _openingOwner = false;
    }
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
              bottomItem: const RailItem(
                icon: Icons.lock_outline,
                label: 'Owner',
              ),
              onBottomTap: _openOwner,
            ),
            // Expanded = take up all the space left of the rail
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // buttons have no action yet so they show greyed out until feature 7
                  TopBar(businessDate: _draft?.day.date, isSubmitted: false),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      // IndexedStack keeps all tabs alive but only shows the selected one,
                      // so switching tabs doesnt lose what was on them
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          CountTab(
                            key: ValueKey(_countTabVersion),
                            draft: _draft,
                            store: _countStore,
                            onChanged: _loadDraft,
                          ),
                          const PlaceholderTab(
                            title: 'Tally tab',
                            note: 'The menu grid comes in Feature 5.',
                          ),
                          const PlaceholderTab(
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
