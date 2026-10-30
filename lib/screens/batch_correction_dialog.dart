import 'package:flutter/material.dart';

import '../database/batch_repository.dart';
import '../logic/formatting.dart';
import '../models/inventory_batch.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/manager_pin_dialog.dart';

/// fixes a batch that was recorded wrongly at receiving
///
/// this exists because there is no other honest way out of a typo, declaring the
/// difference as a loss would record stock that never existed as waste, and
/// leaving it alone means the next closing count reports it as a huge
/// unexplained shortfall
///
/// returns true when something was changed
class BatchCorrectionDialog extends StatefulWidget {
  const BatchCorrectionDialog({super.key, required this.item});

  final BatchWithIngredient item;

  static Future<bool?> show(BuildContext context, BatchWithIngredient item) {
    return showDialog<bool>(
      context: context,
      builder: (_) => BatchCorrectionDialog(item: item),
    );
  }

  @override
  State<BatchCorrectionDialog> createState() => _BatchCorrectionDialogState();
}

class _BatchCorrectionDialogState extends State<BatchCorrectionDialog> {
  final _batches = BatchRepository();
  final _formKey = GlobalKey<FormState>();

  late final _capacityCtrl = TextEditingController(
    text: quantity(widget.item.batch.containerCapacity),
  );
  late final _quantityCtrl = TextEditingController(
    text: quantity(widget.item.batch.quantityRemaining),
  );
  late int _containers = widget.item.batch.containersReceived;
  late DateTime _expiry = DateTime.parse(widget.item.batch.expiryDate);

  bool _hasHistory = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _checkHistory();
  }

  @override
  void dispose() {
    _capacityCtrl.dispose();
    _quantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkHistory() async {
    final used = await _batches.hasHistory(widget.item.batch.batchId);
    if (!mounted) return;
    setState(() => _hasHistory = used);
  }

  double? get _capacity => double.tryParse(_capacityCtrl.text.trim());
  double? get _quantity => double.tryParse(_quantityCtrl.text.trim());

  /// nothing to do if every field still matches what's stored
  bool get _hasChanges {
    final b = widget.item.batch;
    return formatDate(_expiry) != b.expiryDate ||
        _capacity != b.containerCapacity ||
        _containers != b.containersReceived ||
        _quantity != b.quantityRemaining;
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry,
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    if (_working) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_hasChanges) {
      Navigator.pop(context, false);
      return;
    }

    // correcting records by hand needs manager approval, it bypasses the count
    final manager = await ManagerPinDialog.show(
      context,
      'Correct the recorded figures for batch '
      '#${widget.item.batch.batchId}?',
    );
    if (manager == null) return;
    if (!mounted) return;

    setState(() => _working = true);

    try {
      await _batches.correctBatch(
        batchId: widget.item.batch.batchId,
        expiryDate: formatDate(_expiry),
        containerCapacity: _capacity!,
        containersReceived: _containers,
        quantityRemaining: _quantity!,
        // what it said before this correction, recorded on the row
        previousQuantity: widget.item.batch.quantityRemaining,
        // the manager who just approved it, from the pin dialog
        correctedBy: manager.userId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Could not correct the batch: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.item.batch;
    final unit = widget.item.unitOfMeasure;

    return AlertDialog(
      title: Text('Correct batch #${batch.batchId}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.item.ingredientName} · received '
                  '${batch.receivedAt.substring(0, 10)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Use this only to fix something that was entered wrongly. '
                  'Stock that was genuinely used or spilled belongs in the '
                  'closing count or a declared loss, not here.',
                ),
                // what the last correction did, so a second one is made knowing
                // the first happened, only the latest is kept
                if (batch.wasCorrected) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history,
                          size: 18,
                          color: AppColors.inkMuted,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Already corrected by '
                            '${widget.item.correctedByName ?? 'a manager'} on '
                            '${batch.correctedAt!.substring(0, 10)}'
                            '${batch.correctionChangedQuantity ? ', when the quantity was ${quantity(batch.previousQuantity!)} $unit' : ''}'
                            '. Correcting again replaces that record.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_hasHistory) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.caution.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radius),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          color: AppColors.cautionText,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'This batch has already been sold from, lost from '
                            'or counted. Past records keep the figures they '
                            'were made with.',
                            style: TextStyle(color: AppColors.cautionText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),

                _Field(
                  label: 'Expiry date',
                  was: batch.expiryDate,
                  child: OutlinedButton.icon(
                    onPressed: _pickExpiry,
                    icon: const Icon(Icons.event),
                    label: Text(formatDate(_expiry)),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                _Field(
                  label: 'Container size',
                  was: '${quantity(batch.containerCapacity)} $unit',
                  child: TextFormField(
                    controller: _capacityCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(suffixText: unit),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      return (n == null || n <= 0)
                          ? 'Enter a size above 0'
                          : null;
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                _Field(
                  label: 'Containers received',
                  was: '${batch.containersReceived}',
                  child: Row(
                    children: [
                      _SmallStep(
                        icon: Icons.remove,
                        onTap: _containers > 1
                            ? () => setState(() => _containers--)
                            : null,
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '$_containers',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      _SmallStep(
                        icon: Icons.add,
                        onTap: () => setState(() => _containers++),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                _Field(
                  label: 'Quantity on hand now',
                  was: '${quantity(batch.quantityRemaining)} $unit',
                  child: TextFormField(
                    controller: _quantityCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(suffixText: unit),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      return (n == null || n < 0)
                          ? 'Enter a quantity of 0 or more'
                          : null;
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // what a full batch would hold, a quick sanity check that the
                // size and count are the right way round
                if (_capacity != null)
                  Text(
                    'A full batch at these figures would hold '
                    '${quantity(_capacity! * _containers)} $unit.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working || !_hasChanges ? null : _save,
          child: Text(_working ? 'Saving…' : 'Correct records'),
        ),
      ],
    );
  }
}

/// one field, with what it currently says underneath so the change is visible
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.was,
    required this.child,
  });

  final String label;
  final String was;
  final Widget child;

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
        Text(
          'currently $was',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _SmallStep extends StatelessWidget {
  const _SmallStep({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: Container(
        width: AppSizes.minTarget,
        height: AppSizes.minTarget,
        decoration: BoxDecoration(
          color: enabled ? AppColors.surfaceRaised : AppColors.surfaceSunken,
          border: Border.all(
            color: enabled ? AppColors.outline : AppColors.hairline,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? AppColors.ink : AppColors.inkDisabled,
        ),
      ),
    );
  }
}
