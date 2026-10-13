import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../session/session.dart';
import 'ingredients_screen.dart';
import 'backup_screen.dart';
import 'declare_loss_screen.dart';
import 'export_screen.dart';
import 'expiry_matrix_screen.dart';
import 'loss_chart_screen.dart';
import 'menu_items_screen.dart';
import 'pos_screen.dart';
import 'receiving_screen.dart';
import 'sales_history_screen.dart';
import 'shift_screen.dart';

/// manager landing, a grid of cards to each manager feature, cards get added as features are built
class ManagerHomeScreen extends StatelessWidget {
  const ManagerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manager — ${user.name}'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: Session.logOut,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: GridView.count(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: [
            _NavCard(
              icon: Icons.inventory_2_outlined,
              label: 'Ingredients',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IngredientsScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.local_cafe_outlined,
              label: 'Menu Items',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MenuItemsScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.move_to_inbox_outlined,
              label: 'Receive Stock',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceivingScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.point_of_sale,
              label: 'Point of Sale',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PosScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.report_gmailerrorred_outlined,
              label: 'Declare Loss',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeclareLossScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.schedule,
              label: 'Shifts',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ShiftScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.event_busy_outlined,
              label: 'Stock & Expiry',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExpiryMatrixScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.bar_chart,
              label: 'Material Loss',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LossChartScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.download_outlined,
              label: 'Export Data',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExportScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.storage_outlined,
              label: 'Backup & Restore',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupScreen()),
              ),
            ),
            _NavCard(
              icon: Icons.history,
              label: 'Sales History',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
