import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/analytics_store.dart';
import '../data/backup_files.dart';
import '../data/backup_store.dart';
import '../data/email_settings_store.dart';
import '../data/menu_item_store.dart';
import '../data/owner_pin_store.dart';
import '../data/recipe_store.dart';
import '../data/sent_reports_store.dart';
import '../data/stock_item_store.dart';
import '../email/outbox_sender.dart';
import '../layout/side_rail.dart';
import '../security/key_store.dart';
import 'analytics/analytics_tab.dart';
import 'menu/menu_tab.dart';
import 'owner_lock.dart';
import 'reports/reports_tab.dart';
import 'settings/settings_tab.dart';
import 'stock_items/stock_items_tab.dart';

// owner side, only reachable through the pin
// "unlocked" is not saved anywhere: the owner is unlocked only while this screen is open,
// so leaving it in any way (lock button, back, home) means the pin is needed again
class OwnerSectionScreen extends StatefulWidget {
  const OwnerSectionScreen({
    super.key,
    required this.db,
    this.keys,
    this.httpClient,
    this.emailViewer,
    this.backupFiles = const DeviceBackupFiles(),
  });

  // the app's db (or the test db in tests), the owner tabs read and save through it
  final Database db;
  // where the api keys are kept, null = the real secure storage (tests pass a memory one)
  final KeyStore? keys;
  // for resend in reports, null = a real one (tests pass a fake mailjet)
  final http.Client? httpClient;
  // shows an email in reports, null = the webview (tests pass a simple one, a webview cant run in tests)
  final EmailViewBuilder? emailViewer;
  // where backups are saved and picked, tests pass a fake
  final BackupFiles backupFiles;

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
  late final MenuItemStore _menuStore = MenuItemStore(widget.db);
  late final RecipeStore _recipeStore = RecipeStore(widget.db);
  late final KeyStore _keys = widget.keys ?? SecureKeyStore();
  late final EmailSettingsStore _emailStore = EmailSettingsStore(
    widget.db,
    _keys,
  );
  // made here only when no client was given, so only then this screen closes it
  late final http.Client _http = widget.httpClient ?? http.Client();
  late final OutboxSender _sender = OutboxSender(widget.db, _keys, _http);
  late final SentReportsStore _reports = SentReportsStore(widget.db);
  late final AnalyticsStore _analytics = AnalyticsStore(widget.db);
  late final OwnerPinStore _pins = OwnerPinStore(widget.db);
  late final BackupStore _backup = BackupStore(widget.db);

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
    if (widget.httpClient == null) _http.close();
    super.dispose();
  }

  // close everything on top of the barista side, that is the lock
  void _lock() {
    if (!mounted) return;
    // the app's own file picker (back up, restore) is open, that isnt the owner leaving
    if (OwnerLock.isPaused) return;
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
                    AnalyticsTab(store: _analytics),
                    widget.emailViewer == null
                        ? ReportsTab(store: _reports, sender: _sender)
                        : ReportsTab(
                            store: _reports,
                            sender: _sender,
                            viewer: widget.emailViewer!,
                          ),
                    MenuTab(
                      store: _menuStore,
                      recipes: _recipeStore,
                      stock: _stockStore,
                    ),
                    StockItemsTab(store: _stockStore),
                    SettingsTab(
                      store: _emailStore,
                      pins: _pins,
                      backup: _backup,
                      sender: _sender,
                      files: widget.backupFiles,
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
