import 'package:flutter/material.dart';

import '../database/ingredient_repository.dart';
import '../logic/formatting.dart';
import '../models/ingredient.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';

/// manager screen to add, edit and archive ingredients
///
/// an ingredient is only a name and a unit, it has no quantity of its own,
/// stock lives in batches created by receiving
class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  final _repo = IngredientRepository();
  List<IngredientUsage> _ingredients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // load from db into state, called again after every write so the list stays current
  Future<void> _reload() async {
    final list = await _repo.getActiveWithUsage();
    if (!mounted) return;
    setState(() {
      _ingredients = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showDialog<_IngredientFormResult>(
      context: context,
      builder: (_) => const _IngredientFormDialog(),
    );
    if (result == null) return; // cancelled

    try {
      await _repo.insert(result.name, result.unit);
      await _reload();
    } on DuplicateNameException catch (e) {
      _showError('"${e.name}" already exists');
    }
  }

  Future<void> _edit(Ingredient ingredient) async {
    final result = await showDialog<_IngredientFormResult>(
      context: context,
      builder: (_) => _IngredientFormDialog(existing: ingredient),
    );
    if (result == null) return;

    try {
      await _repo.update(Ingredient(
        ingredientId: ingredient.ingredientId,
        name: result.name,
        unitOfMeasure: result.unit,
        isArchived: false,
      ));
      await _reload();
    } on DuplicateNameException catch (e) {
      _showError('"${e.name}" already exists');
    }
  }

  Future<void> _archive(IngredientUsage usage) async {
    final ingredient = usage.ingredient;

    // spell out what still depends on it, archiving one that is in use hides it
    // from receiving and from new recipes while sales keep deducting it
    final consequences = <String>[
      if (usage.isUsed)
        'It is used by ${usage.recipeCount} '
            'recipe${usage.recipeCount == 1 ? '' : ' lines'}, which will keep '
            'deducting it on every sale.',
      if (usage.hasStock)
        'There is still ${quantity(usage.stockRemaining)} '
            '${ingredient.unitOfMeasure} in stock, which will no longer appear '
            'on the stock screen.',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${ingredient.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'It will be hidden from receiving and from new recipes, but kept '
              'so past records still make sense.',
            ),
            if (consequences.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              for (final line in consequences)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                        color: AppColors.caution,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repo.archive(ingredient.ingredientId);
    await _reload();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.danger,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ingredients')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add ingredient'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ingredients.isEmpty
              ? const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No ingredients yet',
                  message: 'Add what the cafe keeps behind the counter — milk, '
                      'beans, syrups. Stock itself is recorded later, through '
                      'Receive Stock.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _ingredients.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final usage = _ingredients[index];
                    final ing = usage.ingredient;

                    return ListTile(
                      title: Text(ing.name),
                      subtitle: Text(
                        'Measured in ${ing.unitOfMeasure} · '
                        '${usage.isUsed ? 'used by ${usage.recipeCount} recipe line${usage.recipeCount == 1 ? '' : 's'}' : 'not used by any recipe'}',
                      ),
                      onTap: () => _edit(ing),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // the stock figure, so archiving something still on the
                          // shelf is an obvious mistake before the dialog says so
                          Text(
                            usage.hasStock
                                ? '${quantity(usage.stockRemaining)} ${ing.unitOfMeasure}'
                                : 'no stock',
                            style: usage.hasStock
                                ? Theme.of(context).textTheme.titleMedium
                                : Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          IconButton(
                            tooltip: 'Archive',
                            icon: const Icon(Icons.archive_outlined),
                            onPressed: () => _archive(usage),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

/// what the dialog hands back, null if cancelled
class _IngredientFormResult {
  const _IngredientFormResult(this.name, this.unit);
  final String name;
  final String unit;
}

/// add/edit dialog, pass existing to prefill for edit
class _IngredientFormDialog extends StatefulWidget {
  const _IngredientFormDialog({this.existing});

  final Ingredient? existing;

  @override
  State<_IngredientFormDialog> createState() => _IngredientFormDialogState();
}

class _IngredientFormDialogState extends State<_IngredientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  // controller is how you read what's typed in a text field, must be disposed
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  // dropdown just needs a plain variable, null until picked
  late String? _unit = widget.existing?.unitOfMeasure;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    // runs every validator, returns false if any fails
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _IngredientFormResult(_nameCtrl.text.trim(), _unit!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit ingredient' : 'New ingredient'),
      // scroll view so the dialog shrinks instead of overflowing when the keyboard takes half the screen
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Fresh Milk',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Unit of measure'),
                items: [
                  for (final u in kUnitsOfMeasure)
                    DropdownMenuItem(value: u, child: Text(u)),
                ],
                onChanged: (v) => setState(() => _unit = v),
                validator: (v) => v == null ? 'Pick a unit' : null,
              ),
              if (isEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Changing the unit does not convert existing stock, so only '
                  'change it if it was entered wrongly.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
