import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/home_status_service.dart';
import '../session/session.dart';
import '../theme/app_metrics.dart';
import '../widgets/nav_cards.dart';
import '../widgets/status_band.dart';
import 'declare_loss_screen.dart';
import 'expiry_matrix_screen.dart';
import 'pos_screen.dart';
import 'sales_history_screen.dart';
import 'shift_screen.dart';

/// the barista's landing screen
///
/// a barista has one job, so the till is one oversized card and everything else
/// is secondary, the status band above it means they see an expiring ingredient
/// on walking up rather than having to go looking for it
class BaristaHomeScreen extends StatefulWidget {
  const BaristaHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<BaristaHomeScreen> createState() => _BaristaHomeScreenState();
}

class _BaristaHomeScreenState extends State<BaristaHomeScreen> {
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
          : Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  StatusBand(
                    status: status,
                    onShiftTap: () => _open(const ShiftScreen()),
                    onSalesTap: () => _open(const SalesHistoryScreen()),
                    onStockTap: () => _open(const ExpiryMatrixScreen()),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // the one thing a barista is here to do, so it takes the room
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: _TillCard(
                        hasOpenShift: status.hasOpenShift,
                        onTap: () => _open(const PosScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  Row(
                    children: [
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
                          icon: Icons.event_busy_outlined,
                          label: 'Stock & Expiry',
                          onTap: () => _open(const ExpiryMatrixScreen()),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: NavCard(
                          icon: Icons.schedule,
                          label: 'My Shift',
                          onTap: () => _open(const ShiftScreen()),
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
                ],
              ),
            ),
    );
  }
}

/// the till, deliberately the biggest thing on the screen
class _TillCard extends StatelessWidget {
  const _TillCard({required this.hasOpenShift, required this.onTap});

  /// sales still work without a shift open, one is created automatically,
  /// but saying so here nudges them to open one properly
  final bool hasOpenShift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primary,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.point_of_sale, size: 56, color: Colors.white),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Open Point of Sale',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                hasOpenShift
                    ? 'Take an order'
                    : 'Take an order — no shift open yet',
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
