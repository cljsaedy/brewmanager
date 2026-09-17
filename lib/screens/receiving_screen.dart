import 'package:flutter/material.dart';

import '../database/batch_repository.dart';
import '../database/ingredient_repository.dart';
import '../models/ingredient.dart';
import '../models/inventory_batch.dart';

/// record a delivery as batches, fill the form → add to list → repeat → save all
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

  void _addToPending(NewBatch batch) {
    // same ingredient + expiry + container size is the same batch by definition, so just bump the count instead of adding a second row
    final i = _pending.indexWhere((p) => p.isSameBatchAs(batch));
    setState(() {
      if (i == -1) {
        _pending.add(batch);
      } else {
        _pending[i] = _pending[i].withMoreContainers(batch.containersReceived);
      }
    });
  }

  void _removeFromPending(int index) {
    setState(() => _pending.removeAt(index));
  }

  Future<void> _saveAll() async {
    if (_pending.isEmpty || _saving) return;
    setState(() => _saving = true);

    await _batches.insertAll(_pending);
    if (!mounted) return;

    final count = _pending.length;
    setState(() {
      _pending.clear();
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved $count batch${count == 1 ? '' : 'es'}')),
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
              padding: const EdgeInsets.all(24),
              child: _BatchForm(
                choices: _choices,
                onAdd: _addToPending,
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // right half, what's been added so far
          Expanded(
            child: _PendingList(
              pending: _pending,
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

/// the four inputs that define a batch, plus an add button
class _BatchForm extends StatefulWidget {
  const _BatchForm({required this.choices, required this.onAdd});

  final List<Ingredient> choices;
  final void Function(NewBatch) onAdd;

  @override
  State<_BatchForm> createState() => _BatchFormState();
}

class _BatchFormState extends State<_BatchForm> {
  final _formKey = GlobalKey<FormState>();
  Ingredient? _ingredient;
  DateTime? _expiry;
  final _capacityCtrl = TextEditingController();
  final _countCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _capacityCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
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
      containerCapacity: double.parse(_capacityCtrl.text.trim()),
      containersReceived: int.parse(_countCtrl.text.trim()),
    ));

    // keep ingredient and capacity since the next batch is often the same product with a different expiry
    setState(() {
      _expiry = null;
      _countCtrl.text = '1';
    });
  }

  @override
  Widget build(BuildContext context) {
    final unit = _ingredient?.unitOfMeasure ?? '';

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New batch', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
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
              onChanged: (v) => setState(() => _ingredient = v),
              validator: (v) => v == null ? 'Pick an ingredient' : null,
            ),
            const SizedBox(height: 12),
            // date picker button styled like a field
            OutlinedButton.icon(
              onPressed: _pickExpiry,
              icon: const Icon(Icons.event),
              label: Text(
                _expiry == null ? 'Expiry date' : formatDate(_expiry!),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Container size',
                hintText: 'e.g. 1000',
                suffixText: unit,
              ),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                return (n == null || n <= 0) ? 'Enter a size above 0' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _countCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Containers received',
              ),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return (n == null || n <= 0) ? 'Enter a count above 0' : null;
              },
              onFieldSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 24),
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

/// the delivery so far with a save all button
class _PendingList extends StatelessWidget {
  const _PendingList({
    required this.pending,
    required this.saving,
    required this.onRemove,
    required this.onSave,
  });

  final List<NewBatch> pending;
  final bool saving;
  final void Function(int index) onRemove;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'This delivery (${pending.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: pending.isEmpty
              ? const Center(child: Text('Nothing added yet'))
              : ListView.separated(
                  itemCount: pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final b = pending[index];
                    return ListTile(
                      title: Text(b.ingredientName),
                      subtitle: Text(
                        '${b.containersReceived} × ${_fmt(b.containerCapacity)} ${b.unitOfMeasure} '
                        '= ${_fmt(b.totalQuantity)} ${b.unitOfMeasure} · exp ${formatDate(b.expiryDate)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => onRemove(index),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: pending.isEmpty || saving ? null : onSave,
              icon: const Icon(Icons.save),
              label: Text(saving ? 'Saving…' : 'Save all'),
            ),
          ),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
