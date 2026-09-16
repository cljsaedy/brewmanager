import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../session/session.dart';
import 'ingredients_screen.dart';
import 'menu_items_screen.dart';

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
