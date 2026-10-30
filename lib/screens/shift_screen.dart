import 'package:flutter/material.dart';

import '../database/shift_repository.dart';
import '../logic/formatting.dart';
import '../models/shift.dart';
import '../session/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';
import 'audit_screen.dart';

/// open and close shifts, and see past ones
///
/// shifts exist rather than just dates because a cafe with rotating staff
/// reconciles more than once a day, and closing one is what triggers the count
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final _shifts = ShiftRepository();

  Shift? _open;
  ShiftSummary? _openSummary;
  List<ShiftWithSummary> _recent = [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final open = await _shifts.getOpenShift();
    // only the open shift needs live stats fetched separately, the history list
    // gets its figures from one query
    final summary =
        open == null ? null : await _shifts.getSummary(open.shiftId);
    final recent = await _shifts.getRecentWithSummary();
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
    if (_working) return;

    final user = Session.currentUser;
    if (user == null) {
      // nothing to record a shift against, say so rather than doing nothing
      _say('Nobody is signed in — sign in again to open a shift',
          isError: true);
      return;
    }

    setState(() => _working = true);

    try {
      await _shifts.openShift(user.userId);
      await _reload();
      if (!mounted) return;
      _say('Shift opened for ${user.name}');
    } on ShiftAlreadyOpenException catch (e) {
      await _reload();
      if (!mounted) return;
      _say('${e.openShift.userName} already has a shift open');
    } catch (e) {
      // anything unexpected used to vanish and leave the button stuck disabled,
      // which looked exactly like the button not working at all
      await _reload();
      if (!mounted) return;
      _say('Could not open the shift: $e', isError: true);
    } finally {
      // always clears, whatever happened, so the button can never stay dead
      if (mounted) setState(() => _working = false);
    }
  }

  void _say(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.danger : null,
        content: Text(message),
      ),
    );
  }

  Future<void> _closeShift(Shift shift) async {
    if (_working) return;

    final summary = await _shifts.getSummary(shift.shiftId);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Close ${shift.userName}'s shift?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opened ${_formatDateTime(shift.openedAt)}'),
            const SizedBox(height: AppSpacing.sm),
            Text('${summary.saleCount} sales · '
                '${money(summary.salesTotal)}'),
            if (summary.voidedCount > 0)
              Text('${summary.voidedCount} voided'),
            if (summary.declaredLossCount > 0)
              Text('${summary.declaredLossCount} declared losses'),
            const SizedBox(height: AppSpacing.md),
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

    try {
      await _shifts.closeShift(shift.shiftId);
      await _reload();
      if (!mounted) return;
      _say('Count submitted and shift closed');
    } catch (e) {
      await _reload();
      if (!mounted) return;
      _say('Could not close the shift: $e', isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
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
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
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
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'PAST SHIFTS',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _recent.isEmpty
                      ? const EmptyState(
                          icon: Icons.schedule,
                          title: 'No shifts yet',
                          message: 'Open a shift at the start of service so '
                              'sales and the closing count are recorded '
                              'against whoever is on.',
                        )
                      : ListView.separated(
                          itemCount: _recent.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) =>
                              _ShiftRow(entry: _recent[index]),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 32,
                color: AppColors.inkMuted),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No shift open',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'Open one at the start of service so sales and the closing '
                    'count are recorded against you.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
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
    final opened = DateTime.parse(shift.openedAt);
    final elapsed = DateTime.now().difference(opened);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: AppSizes.statusBarWidth,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.safe,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${shift.userName} is on shift',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Shift #${shift.shiftId} · open '
                        '${_elapsedLabel(elapsed)} · since '
                        '${_timeOnly(opened)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (summary != null) ...[
                  _Figure(
                    value: '${summary!.saleCount}',
                    label: 'sales',
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  _Figure(
                    value: money(summary!.salesTotal),
                    label: 'taken',
                  ),
                  if (summary!.declaredLossCount > 0) ...[
                    const SizedBox(width: AppSpacing.lg),
                    _Figure(
                      value: '${summary!.declaredLossCount}',
                      label: 'losses',
                      colour: AppColors.caution,
                    ),
                  ],
                  const SizedBox(width: AppSpacing.lg),
                ],
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
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.caution.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSizes.radius),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_outlined,
                        color: AppColors.cautionText,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'This shift belongs to ${shift.userName}. Your sales '
                          'will be recorded under their shift until it is '
                          'closed.',
                          style: const TextStyle(
                            color: AppColors.cautionText,
                          ),
                        ),
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

  static String _elapsedLabel(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  static String _timeOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }
}

/// one number with its label, used across the open shift card
class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    this.colour,
  });

  final String value;
  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: colour),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ShiftRow extends StatelessWidget {
  const _ShiftRow({required this.entry});

  final ShiftWithSummary entry;

  @override
  Widget build(BuildContext context) {
    final shift = entry.shift;
    final summary = entry.summary;
    final opened = DateTime.parse(shift.openedAt);

    return ListTile(
      leading: Icon(
        shift.isOpen ? Icons.lock_open : Icons.lock_outline,
        color: shift.isOpen ? AppColors.safe : AppColors.inkMuted,
      ),
      title: Text('${_dateLabel(opened)} · ${shift.userName}'),
      subtitle: Text(
        shift.isOpen
            ? 'Shift #${shift.shiftId} · open since ${_timeOnly(opened)}'
            : 'Shift #${shift.shiftId} · ${_timeOnly(opened)} to '
                '${_timeOnly(DateTime.parse(shift.closedAt!))} · '
                '${summary.saleCount} sales · ${money(summary.salesTotal)}'
                '${summary.declaredLossCount > 0 ? ' · ${summary.declaredLossCount} losses' : ''}',
      ),
      // a closed shift with no count means that stretch of drift was never
      // measured, which is worth seeing without opening the database
      trailing: shift.isOpen
          ? null
          : entry.wasCounted
              ? const _Tag(
                  label: 'Counted',
                  colour: AppColors.safe,
                  icon: Icons.check,
                )
              : const _Tag(
                  label: 'Not counted',
                  colour: AppColors.caution,
                  icon: Icons.warning_amber_outlined,
                ),
    );
  }

  static String _dateLabel(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  static String _timeOnly(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.colour,
    required this.icon,
  });

  final String label;
  final Color colour;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        border: Border.all(color: colour),
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
      // min, this sits in ListTile.trailing where the width is unbounded while
      // the tile measures its children, and a Row defaulting to max tries to
      // fill infinity and fails to size at all
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colour),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
