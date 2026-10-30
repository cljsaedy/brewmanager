import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/home_status_service.dart';
import '../session/session.dart';
import '../theme/app_metrics.dart';
import '../widgets/nav_cards.dart';
import '../widgets/status_band.dart';
import 'backup_screen.dart';
import 'declare_loss_screen.dart';
import 'evaluation_scenario_screen.dart';
import 'export_screen.dart';
import 'expiry_matrix_screen.dart';
import 'ingredients_screen.dart';
import 'loss_chart_screen.dart';
import 'menu_items_screen.dart';
import 'pos_screen.dart';
import 'receiving_screen.dart';
import 'sales_history_screen.dart';
import 'shift_screen.dart';
import 'staff_screen.dart';

/// the manager's landing screen
///
/// it answers "what is the state right now" across the top, then groups the rest
/// by how often it gets used, the till is the darkest thing on the screen and the
/// setup items are a quiet list, because a flat grid of identical cards made
/// everything look equally important
class ManagerHomeScreen extends StatefulWidget {
  const ManagerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> {
  final _statusService = HomeStatusService();

  HomeStatus? _status;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final status = await _statusService.load();
    if (!mounted) return;
    setState(() => _status = status);
  }

  /// pushes a screen, then refreshes the band because the state may have moved on
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return Scaffold(
      appBar: AppBar(
        title: Text('Good day, ${widget.user.name}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: Session.logOut,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                StatusBand(
                  status: status,
                  onShiftTap: () => _open(const ShiftScreen()),
                  onSalesTap: () => _open(const SalesHistoryScreen()),
                  onStockTap: () => _open(const ExpiryMatrixScreen()),
                ),
                const SizedBox(height: AppSpacing.xl),

                // used all day, so it gets the one filled card
                NavSection(
                  title: 'Service',
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: PrimaryNavCard(
                          icon: Icons.point_of_sale,
                          label: 'Point of Sale',
                          hint: 'Take an order and check out',
                          onTap: () => _open(const PosScreen()),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: NavCard(
                          icon: Icons.report_gmailerrorred_outlined,
                          label: 'Declare Loss',
                          onTap: () => _open(const DeclareLossScreen()),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: NavCard(
                          icon: Icons.history,
                          label: 'Sales History',
                          onTap: () => _open(const SalesHistoryScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // regular but considered work, medium cards
                NavSection(
                  title: 'Inventory',
                  child: Row(
                    children: [
                      Expanded(
                        child: NavCard(
                          icon: Icons.move_to_inbox_outlined,
                          label: 'Receive Stock',
                          onTap: () => _open(const ReceivingScreen()),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: NavCard(
                          icon: Icons.event_busy_outlined,
                          label: 'Stock & Expiry',
                          onTap: () => _open(const ExpiryMatrixScreen()),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: NavCard(
                          icon: Icons.inventory_2_outlined,
                          label: 'Ingredients',
                          onTap: () => _open(const IngredientsScreen()),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: NavCard(
                          icon: Icons.local_cafe_outlined,
                          label: 'Menu & Recipes',
                          onTap: () => _open(const MenuItemsScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // opened weekly at most, so a quiet list rather than more cards
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: NavSection(
                        title: 'Reports',
                        child: NavListCard(
                          items: [
                            NavListItem(
                              icon: Icons.bar_chart,
                              label: 'Material Loss',
                              onTap: () => _open(const LossChartScreen()),
                            ),
                            NavListItem(
                              icon: Icons.download_outlined,
                              label: 'Export Data',
                              onTap: () => _open(const ExportScreen()),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: NavSection(
                        title: 'Setup',
                        child: NavListCard(
                          items: [
                            NavListItem(
                              icon: Icons.people_outline,
                              label: 'Staff & PINs',
                              onTap: () => _open(const StaffScreen()),
                            ),
                            NavListItem(
                              icon: Icons.schedule,
                              label: 'Shifts',
                              onTap: () => _open(const ShiftScreen()),
                            ),
                            NavListItem(
                              icon: Icons.storage_outlined,
                              label: 'Backup & Restore',
                              onTap: () => _open(const BackupScreen()),
                            ),
                            // kDebugMode is false in a release build, so the
                            // cafe never sees a way to wipe their trading data
                            if (kDebugMode)
                              NavListItem(
                                icon: Icons.science_outlined,
                                label: 'Developer Tools',
                                onTap: () =>
                                    _open(const EvaluationScenarioScreen()),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
