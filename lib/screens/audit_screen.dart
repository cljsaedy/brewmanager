import 'package:flutter/material.dart';

import '../database/reconciliation_repository.dart';
import '../logic/audit_math.dart';
import '../logic/formatting.dart';
import '../models/audit_batch.dart';
import '../session/idle_lock.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/container_fill.dart';
import 'audit_results_screen.dart';

/// the closing stock count, one block per batch with exactly two inputs each
///
/// the expected quantity is loaded when this screen opens but is never shown here,
/// if staff can see the number they will type it in instead of counting (rule 5)
///
/// this is the one screen where slowing the user down is the right thing, it is
/// done once a shift and the number it produces is written straight into the
/// batch records, so the controls are oversized and nothing is rushed
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.shiftId});

  final int shiftId;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _repo = ReconciliationRepository();

  List<AuditBatch> _batches = [];
  // what the barista has entered, keyed by batch_id
  final Map<int, AuditEntry> _entries = {};
  // batches where an impossible sealed count was confirmed as unrecorded receiving
  final Set<int> _confirmedOverCount = {};

  /// batches the barista has actually looked at
  ///
  /// every control starts at last shift's value, so without this a batch could be
  /// submitted untouched and last shift's number would be written back as though
  /// it had been counted
  final Set<int> _checked = {};

  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // counting the shelf means minutes without touching the tablet, and being
    // locked out mid count loses the count, see IdleLock.suspend for why this
    // screen is the exception
    IdleLock.suspend();
    _load();
  }

  @override
  void dispose() {
    IdleLock.resume();
    super.dispose();
  }

  Future<void> _load() async {
    final batches = await _repo.loadBatchesToAudit();
    if (!mounted) return;
    setState(() {
      _batches = batches;
      // each control starts on last shift's count so a routine closing needs small nudges
      for (final b in batches) {
        _entries[b.batchId] = b.startingEntry;
      }
      _loading = false;
    });
  }

  AuditEntry _entryFor(AuditBatch b) =>
      _entries[b.batchId] ?? const AuditEntry(sealedCount: 0, openedTotal: 0);

  Future<void> _setSealed(AuditBatch b, int sealed) async {
    if (sealed < 0) return;

    // the only thing the audit may reveal, that the count is impossible, not what is right
    if (AuditMath.isImpossibleCount(
      sealedCount: sealed,
      containersPossible: b.containersPossible,
    )) {
      final confirmed = await _confirmOverCount(b, sealed);
      if (confirmed != true) return;
      _confirmedOverCount.add(b.batchId);
    } else {
      // stepping back under the ceiling clears the flag again
      _confirmedOverCount.remove(b.batchId);
    }

    setState(() {
      _entries[b.batchId] = AuditEntry(
        sealedCount: sealed,
        openedTotal: _entryFor(b).openedTotal,
      );
      _checked.add(b.batchId);
    });
  }

  Future<bool?> _confirmOverCount(AuditBatch b, int sealed) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.help_outline, size: 40),
        title: const Text('More containers than recorded'),
        content: Text(
          'You have counted $sealed sealed containers of ${b.ingredientName}, '
          'but only ${b.containersPossible} were ever recorded for this batch.\n\n'
          'If that is right, stock probably arrived without being recorded. '
          'Confirming will correct the records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Let me recount'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Count is correct'),
          ),
        ],
      ),
    );
  }

  void _setOpened(AuditBatch b, double opened) {
    if (opened < 0) return;
    setState(() {
      _entries[b.batchId] = AuditEntry(
        sealedCount: _entryFor(b).sealedCount,
        openedTotal: opened,
      );
      _checked.add(b.batchId);
    });
  }

  /// marks a block as looked at without changing the figures
  void _confirmUnchanged(AuditBatch b) {
    setState(() => _checked.add(b.batchId));
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final unchecked =
        _batches.where((b) => !_checked.contains(b.batchId)).toList();

    if (unchecked.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_outlined,
            size: 44,
            color: AppColors.caution,
          ),
          title: Text(
            '${unchecked.length} '
            'batch${unchecked.length == 1 ? '' : 'es'} not checked',
          ),
          content: Text(
            'These still hold last shift\'s figures and will be written back as '
            'though they were counted:\n\n'
            '${unchecked.map((b) => '• ${b.ingredientName} (batch #${b.batchId})').join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go back and check'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      if (!mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit the count?'),
        content: const Text(
          'Once submitted the counted amounts replace the system figures and '
          'the count cannot be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep counting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _submitting = true);

    // work out every result first, the expected figures stay hidden until this moment
    final results = <AuditResult>[];
    for (final b in _batches) {
      final entry = _entryFor(b);
      final audited = AuditMath.auditedQuantity(entry, b.containerCapacity);
      results.add(AuditResult(
        auditBatch: b,
        entry: entry,
        auditedQuantity: audited,
        variance: AuditMath.variance(audited, b.theoreticalQuantity),
        varianceType: _confirmedOverCount.contains(b.batchId)
            ? VarianceType.unrecordedReceiving
            : VarianceType.unexplained,
      ));
    }

    await _repo.submitAudit(shiftId: widget.shiftId, results: results);
    if (!mounted) return;

    // now the count is locked, the comparison can be shown
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuditResultsScreen(results: results),
      ),
    );
    if (!mounted) return;

    // the write-back already happened, so tell the shift screen the count went through
    // no matter how the results screen was left, otherwise the shift would stay open
    // with its stock already corrected
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Closing Count')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Closing Count'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: _batches.isEmpty
          ? const Center(child: Text('No batches to count'))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.surfaceSunken,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: const Text(
                    'Count what is on the shelf. Enter unopened containers, '
                    'then how much is left across all opened containers of that '
                    'batch combined.',
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: _batches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final b = _batches[index];
                      return _AuditBlock(
                        auditBatch: b,
                        entry: _entryFor(b),
                        checked: _checked.contains(b.batchId),
                        overCountConfirmed:
                            _confirmedOverCount.contains(b.batchId),
                        onSealedChanged: (v) => _setSealed(b, v),
                        onOpenedChanged: (v) => _setOpened(b, v),
                        onConfirmUnchanged: () => _confirmUnchanged(b),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                _buildFooter(),
              ],
            ),
    );
  }

  Widget _buildFooter() {
    final total = _batches.length;
    final done = _checked.length;
    final allDone = done == total;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(
            allDone ? Icons.check_circle_outline : Icons.pending_outlined,
            color: allDone ? AppColors.safe : AppColors.inkMuted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$done of $total batches checked',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: const Icon(Icons.check),
            label: Text(_submitting ? 'Submitting…' : 'Submit count'),
          ),
        ],
      ),
    );
  }
}

/// one batch block, exactly two controls and nothing that hints at the expected number
class _AuditBlock extends StatelessWidget {
  const _AuditBlock({
    required this.auditBatch,
    required this.entry,
    required this.checked,
    required this.overCountConfirmed,
    required this.onSealedChanged,
    required this.onOpenedChanged,
    required this.onConfirmUnchanged,
  });

  final AuditBatch auditBatch;
  final AuditEntry entry;
  final bool checked;
  final bool overCountConfirmed;
  final void Function(int) onSealedChanged;
  final void Function(double) onOpenedChanged;
  final VoidCallback onConfirmUnchanged;

  @override
  Widget build(BuildContext context) {
    final unit = auditBatch.unitOfMeasure;
    // their own two inputs added up, nothing about what the system expected,
    // so this catches a mis-tap without breaking the blind count
    final counted =
        AuditMath.auditedQuantity(entry, auditBatch.containerCapacity);

    return Container(
      color: checked ? null : AppColors.caution.withValues(alpha: 0.06),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // left, which batch this is, identity only and no quantities
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (checked)
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.sm),
                        child: Icon(
                          Icons.check_circle,
                          size: 20,
                          color: AppColors.safe,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        auditBatch.ingredientName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Batch #${auditBatch.batchId} · '
                  '${quantity(auditBatch.containerCapacity)} $unit containers · '
                  'expires ${auditBatch.expiryDate}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'You counted ${quantity(counted)} $unit',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (overCountConfirmed)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Row(
                      children: [
                        const Icon(Icons.inbox, size: 16,
                            color: AppColors.info),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Unrecorded delivery',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.info),
                        ),
                      ],
                    ),
                  ),
                if (!checked)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: OutlinedButton(
                      onPressed: onConfirmUnchanged,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppSizes.minTarget),
                      ),
                      child: const Text('Same as last shift'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          // right, the two inputs
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stepper(
                  label: 'Sealed containers',
                  // whole containers, shown as a plain number
                  valueLabel: '${entry.sealedCount}',
                  onDown: entry.sealedCount > 0
                      ? () => onSealedChanged(entry.sealedCount - 1)
                      : null,
                  onUp: () => onSealedChanged(entry.sealedCount + 1),
                ),
                const SizedBox(height: AppSpacing.md),
                _OpenedControl(
                  value: entry.openedTotal,
                  onChanged: onOpenedChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// the opened total, the one control people found hardest to use
///
/// it has to express one number that can go above 1, in quarter steps, so there
/// are three ways at it: glyphs that show what the number means on the shelf,
/// chips for the values that actually come up, and the steppers for anything else
class _OpenedControl extends StatelessWidget {
  const _OpenedControl({required this.value, required this.onChanged});

  final double value;
  final void Function(double) onChanged;

  /// what a real closing usually lands on, one tap each
  ///
  /// most batches have at most one container open, so 0 to 1 covers nearly
  /// everything and 1½ and 2 cover the rest without a long row of chips
  static const List<double> _quickPicks = [0, 0.25, 0.5, 0.75, 1, 1.5, 2];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'REMAINING IN OPENED CONTAINERS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppColors.inkMuted,
          ),
        ),
        // says what to do, the label alone didn't make it obvious that several
        // open containers get added together into one figure
        const Text(
          'Add up what is left in all of them',
          style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              onTap: value > 0 ? () => onChanged(value - kOpenedStep) : null,
            ),
            const SizedBox(width: AppSpacing.md),
            // the figure with its unit spelled out, and the picture of it
            //
            // "1¾" on its own reads as a mystery, "1¾ containers" says what the
            // number is counting, which is why it can go above one
            SizedBox(
              width: 112,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatContainers(value),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text(
                      'containers',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // aligned rather than expanded, the glyphs keep their own width
            // instead of being stretched across the gap to the plus button
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ContainerFill(total: value),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              onTap: () => onChanged(value + kOpenedStep),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final pick in _quickPicks)
              _QuickPick(
                label: formatContainers(pick),
                selected: value == pick,
                onTap: () => onChanged(pick),
              ),
          ],
        ),
      ],
    );
  }
}

/// one of the common values, tapping it sets the total outright
class _QuickPick extends StatelessWidget {
  const _QuickPick({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: Container(
        width: 46,
        height: AppSizes.minTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surfaceRaised,
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.hairline,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.inkBody,
          ),
        ),
      ),
    );
  }
}

/// 0, ¼, ½, ¾, 1, 1¼ and so on
String formatContainers(double v) {
  if (v == 0) return '0';
  final whole = v.floor();
  // work in hundredths as ints, dart won't allow doubles as const map keys
  // because their equality is surprising (0.0 == -0.0, NaN != NaN)
  final hundredths = ((v - whole) * 100).round();
  const symbols = {25: '¼', 50: '½', 75: '¾'};
  final symbol = symbols[hundredths] ?? '';
  if (whole == 0) return symbol.isEmpty ? v.toString() : symbol;
  return symbol.isEmpty ? '$whole' : '$whole$symbol';
}

/// big minus and plus either side of a value
///
/// oversized because the barista is usually holding a carton in the other hand
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.valueLabel,
    required this.onDown,
    required this.onUp,
  });

  final String label;
  final String valueLabel;
  final VoidCallback? onDown;
  final VoidCallback? onUp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _StepButton(icon: Icons.remove, onTap: onDown),
            Expanded(
              child: Text(
                valueLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            _StepButton(icon: Icons.add, onTap: onUp),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: Container(
        width: AppSizes.stepper,
        height: AppSizes.stepper,
        decoration: BoxDecoration(
          color: enabled ? AppColors.surfaceRaised : AppColors.surfaceSunken,
          border: Border.all(
            color: enabled ? AppColors.outline : AppColors.hairline,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        child: Icon(
          icon,
          size: 28,
          color: enabled ? AppColors.ink : AppColors.inkDisabled,
        ),
      ),
    );
  }
}
