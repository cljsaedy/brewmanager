import 'package:flutter/material.dart';

import '../database/reconciliation_repository.dart';
import '../logic/audit_math.dart';
import '../models/audit_batch.dart';
import 'audit_results_screen.dart';

/// the closing stock count, one block per batch with exactly two inputs each
///
/// the expected quantity is loaded when this screen opens but is never shown here,
/// if staff can see the number they will type it in instead of counting (rule 5)
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
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;

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
        ],
      ),
      body: _batches.isEmpty
          ? const Center(child: Text('No batches to count'))
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Count what is physically on the shelf. Enter unopened '
                    'containers, then how much is left across all opened '
                    'containers of that batch combined.',
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: _batches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final b = _batches[index];
                      return _AuditBlock(
                        auditBatch: b,
                        entry: _entryFor(b),
                        overCountConfirmed:
                            _confirmedOverCount.contains(b.batchId),
                        onSealedChanged: (v) => _setSealed(b, v),
                        onOpenedChanged: (v) => _setOpened(b, v),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: const Icon(Icons.check),
                      label: Text(
                        _submitting ? 'Submitting…' : 'Submit count',
                      ),
                    ),
                  ),
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
    required this.overCountConfirmed,
    required this.onSealedChanged,
    required this.onOpenedChanged,
  });

  final AuditBatch auditBatch;
  final AuditEntry entry;
  final bool overCountConfirmed;
  final void Function(int) onSealedChanged;
  final void Function(double) onOpenedChanged;

  @override
  Widget build(BuildContext context) {
    final unit = auditBatch.unitOfMeasure;
    final capacity = _fmt(auditBatch.containerCapacity);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auditBatch.ingredientName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    // batch identity only, no quantities, so nothing gives the answer away
                    Text(
                      'Batch #${auditBatch.batchId} · '
                      '$capacity $unit containers · '
                      'expires ${auditBatch.expiryDate}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (overCountConfirmed)
                Chip(
                  avatar: const Icon(Icons.inbox, size: 18),
                  label: const Text('Unrecorded delivery'),
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .tertiaryContainer,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stepper(
                  label: 'Sealed containers',
                  // whole containers, shown as a plain number
                  valueLabel: '${entry.sealedCount}',
                  onDown: entry.sealedCount > 0
                      ? () => onSealedChanged(entry.sealedCount - 1)
                      : null,
                  onUp: () => onSealedChanged(entry.sealedCount + 1),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Stepper(
                  label: 'Opened, all containers together',
                  // quarters, and deliberately not capped at 1
                  valueLabel: _formatContainers(entry.openedTotal),
                  onDown: entry.openedTotal > 0
                      ? () => onOpenedChanged(
                            entry.openedTotal - kOpenedStep,
                          )
                      : null,
                  onUp: () =>
                      onOpenedChanged(entry.openedTotal + kOpenedStep),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 0, ¼, ½, ¾, 1, 1¼ and so on
  static String _formatContainers(double v) {
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

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// big minus and plus either side of a value, sized for a thumb on a counter
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
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton.filledTonal(
              iconSize: 32,
              onPressed: onDown,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                valueLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              iconSize: 32,
              onPressed: onUp,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
