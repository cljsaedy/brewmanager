import 'package:flutter/material.dart';

import '../database/batch_repository.dart';
import '../database/ingredient_repository.dart';
import '../logic/expiry_risk.dart';
import '../logic/formatting.dart';
import '../models/ingredient.dart';
import '../models/inventory_batch.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import 'expiry_matrix_screen.dart' show bandColour, bandTextColour;

/// record a delivery as batches, fill the form → add to list → repeat → save all
///
/// a delivery is often several batches of the same product with different dates,
/// so the form keeps the ingredient and container size after each add and only
/// clears the date and the count
class ReceivingScreen extends StatefulWidget {
  const ReceivingScreen({super.key});

  @override
  State<ReceivingScreen> createState() => _ReceivingScreenState();
}

class _ReceivingScreenState extends State<ReceivingScreen> {
  final _ingredients = IngredientRepository();
  final _batches = BatchRepository();

  List<Ingredient> _choices = [];
  // the delivery so far, nothing is in the db until save
  final List<NewBatch> _pending = [];
  // batch_id each pending row would merge into, so the list can say so
  final Map<int, int> _mergeTargets = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadIngredients();
  }

  Future<void> _loadIngredients() async {
    final list = await _ingredients.getActive();
    if (!mounted) return;
    setState(() => _choices = list);
  }

  Future<void> _addToPending(NewBatch batch) async {
    // same ingredient + expiry + container size is the same batch by definition,
    // so just bump the count instead of adding a second row
    final i = _pending.indexWhere((p) => p.isSameBatchAs(batch));

    // does this already exist in stock, in which case saving will merge into it
    final existing = await _batches.findMatchingBatch(batch);
    if (!mounted) return;

    setState(() {
      if (i == -1) {
        _pending.add(batch);
        if (existing != null) {
          _mergeTargets[_pending.length - 1] = existing.batchId;
        }
      } else {
        _pending[i] = _pending[i].withMoreContainers(batch.containersReceived);
      }
    });
  }

  void _removeFromPending(int index) {
    setState(() {
      _pending.removeAt(index);
      // the merge notes are keyed by position, so rebuild them after a removal
      final rebuilt = <int, int>{};
      for (final entry in _mergeTargets.entries) {
        if (entry.key < index) {
          rebuilt[entry.key] = entry.value;
        } else if (entry.key > index) {
          rebuilt[entry.key - 1] = entry.value;
        }
      }
      _mergeTargets
        ..clear()
        ..addAll(rebuilt);
    });
  }

  Future<void> _saveAll() async {
    if (_pending.isEmpty || _saving) return;
    setState(() => _saving = true);

    await _batches.insertAll(_pending);
    if (!mounted) return;

    final count = _pending.length;
    setState(() {
      _pending.clear();
      _mergeTargets.clear();
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved $count batch${count == 1 ? '' : 'es'}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive Stock')),
      body: Row(
        children: [
          // left half, the form
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _BatchForm(
                choices: _choices,
                onAdd: _addToPending,
                capacitiesFor: _batches.capacitiesUsedFor,
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // right half, what's been added so far
          Expanded(
            child: _PendingList(
              pending: _pending,
              mergeTargets: _mergeTargets,
              saving: _saving,
              onRemove: _removeFromPending,
              onSave: _saveAll,
            ),
          ),
        ],
      ),
    );
  }
}

/// the four things that define a batch, plus an add button
class _BatchForm extends StatefulWidget {
  const _BatchForm({
    required this.choices,
    required this.onAdd,
    required this.capacitiesFor,
  });

  final List<Ingredient> choices;
  final void Function(NewBatch) onAdd;

  /// container sizes this ingredient has arrived in before
  final Future<List<double>> Function(int ingredientId) capacitiesFor;

  @override
  State<_BatchForm> createState() => _BatchFormState();
}

class _BatchFormState extends State<_BatchForm> {
  final _formKey = GlobalKey<FormState>();
  Ingredient? _ingredient;
  DateTime? _expiry;
  final _capacityCtrl = TextEditingController();
  int _containers = 1;

  /// sizes offered as shortcuts for the chosen ingredient
  List<double> _knownCapacities = [];

  @override
  void dispose() {
    _capacityCtrl.dispose();
    super.dispose();
  }

  /// when the ingredient changes, offer the sizes it has come in before and
  /// prefill the one used most, which is almost always the right answer
  Future<void> _onIngredientChanged(Ingredient? ingredient) async {
    setState(() {
      _ingredient = ingredient;
      _knownCapacities = [];
    });
    if (ingredient == null) return;

    final capacities = await widget.capacitiesFor(ingredient.ingredientId);
    if (!mounted) return;
    setState(() {
      _knownCapacities = capacities;
      if (capacities.isNotEmpty && _capacityCtrl.text.trim().isEmpty) {
        _capacityCtrl.text = quantity(capacities.first);
      }
    });
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  double? get _capacity => double.tryParse(_capacityCtrl.text.trim());

  void _add() {
    if (!_formKey.currentState!.validate()) return;
    if (_expiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick an expiry date')),
      );
      return;
    }

    widget.onAdd(NewBatch(
      ingredientId: _ingredient!.ingredientId,
      ingredientName: _ingredient!.name,
      unitOfMeasure: _ingredient!.unitOfMeasure,
      expiryDate: _expiry!,
      containerCapacity: _capacity!,
      containersReceived: _containers,
    ));

    // keep ingredient and capacity, the next batch is usually the same product
    // with a different date
    setState(() {
      _expiry = null;
      _containers = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final unit = _ingredient?.unitOfMeasure ?? '';
    final capacity = _capacity;

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New batch', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),

            DropdownButtonFormField<Ingredient>(
              initialValue: _ingredient,
              decoration: const InputDecoration(labelText: 'Ingredient'),
              items: [
                for (final i in widget.choices)
                  DropdownMenuItem(
                    value: i,
                    child: Text('${i.name} (${i.unitOfMeasure})'),
                  ),
              ],
              onChanged: _onIngredientChanged,
              validator: (v) => v == null ? 'Pick an ingredient' : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            TextFormField(
              controller: _capacityCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Container size',
                hintText: 'e.g. 1000',
                suffixText: unit,
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                return (n == null || n <= 0) ? 'Enter a size above 0' : null;
              },
            ),
            if (_knownCapacities.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in _knownCapacities.take(4))
                    _SizeChip(
                      label: '${quantity(c)} $unit',
                      selected: capacity == c,
                      onTap: () => setState(
                        () => _capacityCtrl.text = quantity(c),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            _ContainerCounter(
              value: _containers,
              onChanged: (v) => setState(() => _containers = v),
            ),
            const SizedBox(height: AppSpacing.lg),

            _ExpiryPicker(expiry: _expiry, onPick: _pickExpiry),
            const SizedBox(height: AppSpacing.lg),

            // the arithmetic spelled out, so a mistyped size is obvious here
            // rather than after it has gone into the records
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppSizes.radius),
              ),
              child: Row(
                children: [
                  const Text('This batch holds'),
                  const Spacer(),
                  Text(
                    capacity == null
                        ? '—'
                        : '${quantity(capacity * _containers)} $unit',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Add to list'),
            ),
          ],
        ),
      ),
    );
  }
}

/// a remembered container size, one tap instead of typing it again
class _SizeChip extends StatelessWidget {
  const _SizeChip({
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
        height: AppSizes.minTarget,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.inkBody,
          ),
        ),
      ),
    );
  }
}

/// how many containers arrived, a stepper because it's a small whole number and
/// a keyboard on a tablet covers half the form
class _ContainerCounter extends StatelessWidget {
  const _ContainerCounter({required this.value, required this.onChanged});

  final int value;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CONTAINERS RECEIVED',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _CountButton(
              icon: Icons.remove,
              onTap: value > 1 ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 72,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            _CountButton(
              icon: Icons.add,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({required this.icon, required this.onTap});

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

/// the expiry date, with how soon that is shown straight away
///
/// a carton that needs using within two days is worth knowing about at receiving
/// time, not at the closing count
class _ExpiryPicker extends StatelessWidget {
  const _ExpiryPicker({required this.expiry, required this.onPick});

  final DateTime? expiry;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final date = expiry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EXPIRY DATE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.event),
              label: Text(date == null ? 'Choose a date' : formatDate(date)),
            ),
            if (date != null) ...[
              const SizedBox(width: AppSpacing.md),
              _BandLabel(expiryDate: formatDate(date)),
            ],
          ],
        ),
      ],
    );
  }
}

/// how soon this expires, in the same colours as the stock screen
class _BandLabel extends StatelessWidget {
  const _BandLabel({required this.expiryDate});

  final String expiryDate;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final band = ExpiryRisk.bandFor(expiryDate, today);
    final colour = bandColour(band);

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
      child: Text(
        ExpiryRisk.describe(expiryDate, today),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: bandTextColour(band),
        ),
      ),
    );
  }
}

/// the delivery so far with a save all button
class _PendingList extends StatelessWidget {
  const _PendingList({
    required this.pending,
    required this.mergeTargets,
    required this.saving,
    required this.onRemove,
    required this.onSave,
  });

  final List<NewBatch> pending;
  final Map<int, int> mergeTargets;
  final bool saving;
  final void Function(int index) onRemove;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceSunken,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Text(
                  'This delivery',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Text(
                  pending.isEmpty
                      ? ''
                      : '${pending.length} '
                          'batch${pending.length == 1 ? '' : 'es'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: pending.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'Fill in the form and add each batch that arrived.\n\n'
                        'Stock with different expiry dates or container sizes '
                        'is a separate batch.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkMuted),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: pending.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _PendingRow(
                      batch: pending[index],
                      mergeTarget: mergeTargets[index],
                      onRemove: () => onRemove(index),
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: pending.isEmpty || saving ? null : onSave,
                icon: const Icon(Icons.save),
                label: Text(
                  saving
                      ? 'Saving…'
                      : pending.isEmpty
                          ? 'Save'
                          : 'Save ${pending.length} '
                              'batch${pending.length == 1 ? '' : 'es'}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.batch,
    required this.mergeTarget,
    required this.onRemove,
  });

  final NewBatch batch;

  /// batch_id this will be added to, null when it creates a new batch
  final int? mergeTarget;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final expiry = formatDate(batch.expiryDate);
    final band = ExpiryRisk.bandFor(expiry, DateTime.now());
    final unit = batch.unitOfMeasure;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: AppSizes.statusBarWidth,
            height: 40,
            decoration: BoxDecoration(
              color: bandColour(band),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batch.ingredientName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${batch.containersReceived} × '
                  '${quantity(batch.containerCapacity)} $unit '
                  '= ${quantity(batch.totalQuantity)} $unit',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  mergeTarget == null
                      // says so, otherwise a merge looks like the add was ignored
                      ? 'Expires $expiry · new batch'
                      : 'Expires $expiry · joins batch #$mergeTarget',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
