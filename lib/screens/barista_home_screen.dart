import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../session/session.dart';
import 'declare_loss_screen.dart';
import 'expiry_matrix_screen.dart';
import 'pos_screen.dart';
import 'sales_history_screen.dart';
import 'shift_screen.dart';

/// barista landing, the till is the main thing they do so it's one tap away
class BaristaHomeScreen extends StatelessWidget {
  const BaristaHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Barista — ${user.name}'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: Session.logOut,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PosScreen()),
              ),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Open Point of Sale'),
            ),
            const SizedBox(height: 16),
            // baristas are the ones who drop things, so they can record it themselves
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeclareLossScreen()),
              ),
              icon: const Icon(Icons.report_gmailerrorred_outlined),
              label: const Text('Declare Container Lost'),
            ),
            const SizedBox(height: 16),
            // baristas open and close their own shifts
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ShiftScreen()),
              ),
              icon: const Icon(Icons.schedule),
              label: const Text('Shifts'),
            ),
            const SizedBox(height: 16),
            // baristas need to see what's expiring to know what to use up
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExpiryMatrixScreen()),
              ),
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Stock & Expiry'),
            ),
            const SizedBox(height: 16),
            // baristas can see sales, but voiding one still asks for a manager pin
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
              ),
              icon: const Icon(Icons.history),
              label: const Text('Sales History'),
            ),
          ],
        ),
      ),
    );
  }
}
