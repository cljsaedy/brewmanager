import 'package:flutter/material.dart';

import '../database/ingredient_repository.dart';
import '../models/ingredient.dart';

/// manager screen to add, edit and archive ingredients
class IngredientsScreen extends StatefulWidget {
  const IngredientsScreen({super.key});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  final _repo = IngredientRepository();
  List<Ingredient> _ingredients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // load from db into state, called again after every write so the list stays current
  Future<void> _reload() async {
    final list = await _repo.getActive();
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

  Future<void> _archive(Ingredient ingredient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${ingredient.name}?'),
        content: const Text(
          'It will be hidden from lists but kept for past records.',
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
              ? const Center(child: Text('No ingredients yet'))
              : ListView.separated(
                  itemCount: _ingredients.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final ing = _ingredients[index];
                    return ListTile(
                      title: Text(ing.name),
                      subtitle: Text('Unit: ${ing.unitOfMeasure}'),
                      onTap: () => _edit(ing),
                      trailing: IconButton(
                        tooltip: 'Archive',
                        icon: const Icon(Icons.archive_outlined),
                        onPressed: () => _archive(ing),
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
              const SizedBox(height: 12),
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
