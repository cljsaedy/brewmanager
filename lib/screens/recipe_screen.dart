import 'package:flutter/material.dart';

import '../database/ingredient_repository.dart';
import '../database/recipe_repository.dart';
import '../database/stock_repository.dart';
import '../logic/availability_calculator.dart';
import '../logic/formatting.dart';
import '../models/ingredient.dart';
import '../models/menu_item.dart';
import '../models/recipe_blueprint.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';

/// the recipe for one menu item, which ingredients and how much of each
///
/// this is what turns a sale into stock movement, the till reads these lines and
/// fefo deducts each amount, so an item with no lines can't be sold at all
class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key, required this.menuItem});

  final MenuItem menuItem;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  final _recipes = RecipeRepository();
  final _ingredients = IngredientRepository();
  final _stock = StockRepository();

  List<RecipeBlueprint> _lines = [];
  List<Ingredient> _allIngredients = [];
  Availability? _availability;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final lines = await _recipes.getForMenuItem(widget.menuItem.menuItemId);
    final ingredients = await _ingredients.getActive();
    final stock = await _stock.getAllBatchStock();
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _allIngredients = ingredients;
      // how many of this drink the stock on hand could actually make, so the
      // recipe being edited is tied to what is in the fridge
      _availability = AvailabilityCalculator.forMenuItem(lines, stock);
      _loading = false;
    });
  }

  /// active ingredients not already in this recipe, so the dropdown can't offer a duplicate
  List<Ingredient> get _availableIngredients {
    final used = _lines.map((l) => l.ingredientId).toSet();
    return _allIngredients.where((i) => !used.contains(i.ingredientId)).toList();
  }

  Future<void> _add() async {
    final available = _availableIngredients;
    if (available.isEmpty) {
      _showMessage('All ingredients are already in this recipe');
      return;
    }

    final result = await showDialog<_LineFormResult>(
      context: context,
      builder: (_) => _LineFormDialog(choices: available),
    );
    if (result == null) return;

    try {
      await _recipes.add(
        widget.menuItem.menuItemId,
        result.ingredientId,
        result.quantity,
      );
      await _reload();
    } on DuplicateIngredientException {
      _showMessage('That ingredient is already in the recipe');
    }
  }

  Future<void> _editQuantity(RecipeBlueprint line) async {
    final result = await showDialog<_LineFormResult>(
      context: context,
      builder: (_) => _LineFormDialog(choices: const [], existing: line),
    );
    if (result == null) return;

    await _recipes.updateQuantity(line.blueprintId, result.quantity);
    await _reload();
  }

  Future<void> _remove(RecipeBlueprint line) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${line.ingredientName}?'),
        content: const Text(
          'Future sales of this item will no longer deduct it. Past sales keep '
          'the deductions they already made.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _recipes.remove(line.blueprintId);
    await _reload();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Recipe — ${widget.menuItem.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add ingredient'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                const Divider(height: 1),
                Expanded(
                  child: _lines.isEmpty
                      ? EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No ingredients yet',
                          message:
                              '${widget.menuItem.name} cannot be sold until its '
                              'recipe says what it is made of. Add each '
                              'ingredient and how much one serving uses.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: _lines.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final line = _lines[index];
                            return ListTile(
                              title: Text(line.ingredientName),
                              subtitle: const Text('per serving'),
                              onTap: () => _editQuantity(line),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${quantity(line.quantityRequired)} '
                                    '${line.unitOfMeasure}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  IconButton(
                                    tooltip: 'Remove',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _remove(line),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  /// the price and what current stock could make, the recipe's consequence
  Widget _buildHeader() {
    final availability = _availability;
    final servings = availability?.servings ?? 0;
    final canMake = availability?.canMakeAtLeastOne ?? false;
    final blocker = availability?.limitingIngredient;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sells for ${money(widget.menuItem.sellingPrice)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  _lines.isEmpty
                      ? 'No ingredients set'
                      : '${_lines.length} '
                          'ingredient${_lines.length == 1 ? '' : 's'} per serving',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: (canMake ? AppColors.safe : AppColors.danger)
                  .withValues(alpha: 0.10),
              border: Border.all(
                color: canMake ? AppColors.safe : AppColors.danger,
              ),
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  canMake ? '$servings' : '0',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    color: canMake ? AppColors.safeText : AppColors.dangerText,
                  ),
                ),
                Text(
                  _lines.isEmpty
                      ? 'needs a recipe'
                      : canMake
                          ? 'can be made from stock'
                          : 'out of ${blocker ?? 'stock'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// what the dialog hands back
class _LineFormResult {
  const _LineFormResult(this.ingredientId, this.quantity);
  final int ingredientId;
  final double quantity;
}

/// add dialog (pick ingredient + quantity) or edit dialog (quantity only) when existing is given
class _LineFormDialog extends StatefulWidget {
  const _LineFormDialog({required this.choices, this.existing});

  final List<Ingredient> choices;
  final RecipeBlueprint? existing;

  @override
  State<_LineFormDialog> createState() => _LineFormDialogState();
}

class _LineFormDialogState extends State<_LineFormDialog> {
  final _formKey = GlobalKey<FormState>();
  Ingredient? _picked;
  late final _qtyCtrl = TextEditingController(
    text: widget.existing == null
        ? null
        : quantity(widget.existing!.quantityRequired),
  );

  bool get _isEdit => widget.existing != null;

  // unit label next to the quantity field, from the picked ingredient or the existing line
  String get _unit =>
      _isEdit ? widget.existing!.unitOfMeasure : (_picked?.unitOfMeasure ?? '');

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final id = _isEdit ? widget.existing!.ingredientId : _picked!.ingredientId;
    Navigator.pop(
      context,
      _LineFormResult(id, double.parse(_qtyCtrl.text.trim())),
    );
  }

  String? _validateQty(String? v) {
    if (v == null || v.trim().isEmpty) return 'Quantity is required';
    final parsed = double.tryParse(v.trim());
    if (parsed == null || parsed <= 0) return 'Enter a quantity above 0';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit ? 'Edit ${widget.existing!.ingredientName}' : 'Add ingredient',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isEdit) ...[
                DropdownButtonFormField<Ingredient>(
                  decoration: const InputDecoration(labelText: 'Ingredient'),
                  items: [
                    for (final i in widget.choices)
                      DropdownMenuItem(
                        value: i,
                        child: Text('${i.name} (${i.unitOfMeasure})'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _picked = v),
                  validator: (v) => v == null ? 'Pick an ingredient' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextFormField(
                controller: _qtyCtrl,
                autofocus: _isEdit,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantity per serving',
                  suffixText: _unit,
                ),
                validator: _validateQty,
                onFieldSubmitted: (_) => _save(),
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
          child: Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
