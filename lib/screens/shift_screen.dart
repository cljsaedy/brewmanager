import 'package:flutter/material.dart';

import '../database/shift_repository.dart';
import '../models/shift.dart';
import '../session/session.dart';
import 'audit_screen.dart';

/// open and close shifts, and see past ones
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final _shifts = ShiftRepository();

  Shift? _open;
  ShiftSummary? _openSummary;
  List<Shift> _recent = [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final open = await _shifts.getOpenShift();
    // only the open shift needs live stats, the history list just shows times
    final summary =
        open == null ? null : await _shifts.getSummary(open.shiftId);
    final recent = await _shifts.getRecent();
    if (!mounted) return;
    setState(() {
      _open = open;
      _openSummary = summary;
      _recent = recent;
      _loading = false;
      _working = false;
    });
  }

  Future<void> _openShift() async {
    final user = Session.currentUser;
    if (user == null || _working) return;
    setState(() => _working = true);

    try {
      await _shifts.openShift(user.userId);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Shift opened for ${user.name}')),
      );
    } on ShiftAlreadyOpenException catch (e) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${e.openShift.userName} already has a shift open'),
        ),
      );
    }
  }

  Future<void> _closeShift(Shift shift) async {
    if (_working) return;

    final summary = await _shifts.getSummary(shift.shiftId);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${shift.userName}\'s shift?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opened ${_formatDateTime(shift.openedAt)}'),
            const SizedBox(height: 8),
            Text('${summary.saleCount} sales · '
                '₱${summary.salesTotal.toStringAsFixed(2)}'),
            if (summary.voidedCount > 0)
              Text('${summary.voidedCount} voided'),
            if (summary.declaredLossCount > 0)
              Text('${summary.declaredLossCount} declared losses'),
            const SizedBox(height: 12),
            const Text(
              'You will count the closing stock next. The shift closes once '
              'the count is submitted.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Count stock'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // the audit comes first, the shift only closes once the count is submitted
    // a cancelled count leaves the shift open so nothing is half finished
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AuditScreen(shiftId: shift.shiftId),
      ),
    );
    if (submitted != true) {
      await _reload();
      return;
    }

    setState(() => _working = true);
    await _shifts.closeShift(shift.shiftId);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Count submitted and shift closed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Session.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shifts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _open == null
                      ? _NoOpenShiftCard(
                          working: _working,
                          onOpen: _openShift,
                        )
                      : _OpenShiftCard(
                          shift: _open!,
                          summary: _openSummary,
                          // flagged when the open shift belongs to someone else
                          isMine: _open!.userId == user?.userId,
                          working: _working,
                          onClose: () => _closeShift(_open!),
                        ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Shift history',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _recent.isEmpty
                      ? const Center(child: Text('No shifts yet'))
                      : ListView.separated(
                          itemCount: _recent.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final shift = _recent[index];
                            return ListTile(
                              leading: Icon(
                                shift.isOpen
                                    ? Icons.lock_open
                                    : Icons.lock_outline,
                              ),
                              title: Text(
                                'Shift #${shift.shiftId} · ${shift.userName}',
                              ),
                              subtitle: Text(
                                shift.isOpen
                                    ? 'Opened ${_formatDateTime(shift.openedAt)} · still open'
                                    : 'Opened ${_formatDateTime(shift.openedAt)}\n'
                                        'Closed ${_formatDateTime(shift.closedAt!)}',
                              ),
                              isThreeLine: !shift.isOpen,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  String _formatDateTime(String iso) {
    final d = DateTime.parse(iso);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

class _NoOpenShiftCard extends StatelessWidget {
  const _NoOpenShiftCard({required this.working, required this.onOpen});

  final bool working;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('No shift open'),
                  Text(
                    'Open one at the start of your shift so sales and the '
                    'closing count are recorded against you.',
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: working ? null : onOpen,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Open shift'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenShiftCard extends StatelessWidget {
  const _OpenShiftCard({
    required this.shift,
    required this.summary,
    required this.isMine,
    required this.working,
    required this.onClose,
  });

  final Shift shift;
  final ShiftSummary? summary;
  final bool isMine;
  final bool working;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_open, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shift #${shift.shiftId} · ${shift.userName}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('Opened ${_formatDateTime(shift.openedAt)}'),
                      if (summary != null)
                        Text(
                          '${summary!.saleCount} sales · '
                          '₱${summary!.salesTotal.toStringAsFixed(2)}'
                          '${summary!.declaredLossCount > 0 ? ' · ${summary!.declaredLossCount} declared losses' : ''}',
                        ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: working ? null : onClose,
                  icon: const Icon(Icons.stop),
                  label: const Text('Close shift'),
                ),
              ],
            ),
            // a shift opened by someone else would put your sales under their name
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This shift belongs to ${shift.userName}. Your sales '
                        'will be recorded under their shift until it is closed.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
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

  String _formatDateTime(String iso) {
    final d = DateTime.parse(iso);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
