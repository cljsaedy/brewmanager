import 'package:flutter/material.dart';

import '../database/ingredient_repository.dart' show DuplicateNameException;
import '../database/menu_item_repository.dart';
import '../database/recipe_repository.dart';
import '../logic/formatting.dart';
import '../models/menu_item.dart';
import '../models/recipe_blueprint.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';
import 'recipe_screen.dart';

/// manager screen to add, edit and archive menu items, and reach their recipes
///
/// an item with no recipe cannot be sold, the till grays it out, so the list
/// flags that here rather than leaving it to be discovered during service
class MenuItemsScreen extends StatefulWidget {
  const MenuItemsScreen({super.key});

  @override
  State<MenuItemsScreen> createState() => _MenuItemsScreenState();
}

class _MenuItemsScreenState extends State<MenuItemsScreen> {
  final _repo = MenuItemRepository();
  final _recipes = RecipeRepository();

  List<MenuItem> _items = [];
  Map<int, List<RecipeBlueprint>> _recipesByItem = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // load from db into state, called after every write
  Future<void> _reload() async {
    final list = await _repo.getActive();
    final recipes = await _recipes.getAllGroupedByMenuItem();
    if (!mounted) return;
    setState(() {
      _items = list;
      _recipesByItem = recipes;
      _loading = false;
    });
  }

  /// drinks whose recipe was never set, which really can't be sold
  ///
  /// food sold as a whole unit is excluded, it has no recipe by design
  int get _missingRecipeCount => _items
      .where((i) =>
          i.isIngredientTracked &&
          (_recipesByItem[i.menuItemId] ?? const []).isEmpty)
      .length;

  Future<void> _add() async {
    final result = await showDialog<_MenuItemFormResult>(
      context: context,
      builder: (_) => const _MenuItemFormDialog(),
    );
    if (result == null) return; // cancelled

    try {
      final id = await _repo.insert(
        result.name,
        result.price,
        isIngredientTracked: result.isIngredientTracked,
      );
      await _reload();
      if (!mounted) return;

      // a new drink has no recipe and can't be sold, so go straight there
      // food sold as a whole unit needs no recipe, so it's already finished
      if (!result.isIngredientTracked) return;

      await _openRecipe(MenuItem(
        menuItemId: id,
        name: result.name,
        sellingPrice: result.price,
        isArchived: false,
      ));
    } on DuplicateNameException catch (e) {
      _showError('"${e.name}" already exists');
    }
  }

  Future<void> _edit(MenuItem item) async {
    final result = await showDialog<_MenuItemFormResult>(
      context: context,
      builder: (_) => _MenuItemFormDialog(existing: item),
    );
    if (result == null) return;

    try {
      await _repo.update(MenuItem(
        menuItemId: item.menuItemId,
        name: result.name,
        sellingPrice: result.price,
        isArchived: false,
        isIngredientTracked: result.isIngredientTracked,
      ));
      await _reload();
    } on DuplicateNameException catch (e) {
      _showError('"${e.name}" already exists');
    }
  }

  Future<void> _openRecipe(MenuItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeScreen(menuItem: item)),
    );
    await _reload();
  }

  Future<void> _archive(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${item.name}?'),
        content: const Text(
          'It will be taken off the till but kept so past sales still show what '
          'was sold and what it sold for.',
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

    await _repo.archive(item.menuItemId);
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
      appBar: AppBar(title: const Text('Menu & Recipes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add menu item'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.local_cafe_outlined,
                  title: 'No menu items yet',
                  message: 'Add each drink you sell. Hot and iced are separate '
                      'items, and each one needs a recipe before it can be '
                      'rung up.',
                )
              : Column(
                  children: [
                    if (_missingRecipeCount > 0) _buildWarningStrip(),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => _MenuRow(
                          item: _items[index],
                          recipe:
                              _recipesByItem[_items[index].menuItemId] ??
                                  const [],
                          onEdit: () => _edit(_items[index]),
                          onRecipe: () => _openRecipe(_items[index]),
                          onArchive: () => _archive(_items[index]),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// says how many items can't be sold, the till would otherwise be the first
  /// place anyone finds out
  Widget _buildWarningStrip() {
    return Container(
      width: double.infinity,
      color: AppColors.caution.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            color: AppColors.cautionText,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '$_missingRecipeCount '
              'item${_missingRecipeCount == 1 ? '' : 's'} '
              '${_missingRecipeCount == 1 ? 'has' : 'have'} no recipe and '
              '${_missingRecipeCount == 1 ? 'cannot' : 'cannot'} be sold until '
              'one is set.',
              style: const TextStyle(color: AppColors.cautionText),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.recipe,
    required this.onEdit,
    required this.onRecipe,
    required this.onArchive,
  });

  final MenuItem item;
  final List<RecipeBlueprint> recipe;
  final VoidCallback onEdit;
  final VoidCallback onRecipe;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final hasRecipe = recipe.isNotEmpty;
    final isWholeUnit = item.isWholeUnit;

    // the recipe in one line, so the list says what the drink is made of
    final summary = recipe
        .map((r) => '${quantity(r.quantityRequired)} '
            '${r.unitOfMeasure} ${r.ingredientName}')
        .join(' · ');

    return ListTile(
      title: Row(
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: AppSpacing.md),
          Text(
            money(item.sellingPrice),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.inkMuted,
                ),
          ),
        ],
      ),
      subtitle: isWholeUnit
          // food by design, not a drink missing its recipe
          ? const Text('Sold as a whole unit — no ingredients tracked')
          : hasRecipe
              ? Text(summary)
              : const Text(
                  'No recipe — cannot be sold',
                  style: TextStyle(
                    color: AppColors.cautionText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
      onTap: onEdit,
      // Row because trailing only takes one widget
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isWholeUnit)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Icon(
                Icons.bakery_dining_outlined,
                color: AppColors.inkMuted,
              ),
            )
          else if (hasRecipe)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Recipe'),
              onPressed: onRecipe,
            )
          else
            FilledButton.icon(
              // the fix is one tap away from the warning
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSizes.minTarget),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Set recipe'),
              onPressed: onRecipe,
            ),
          IconButton(
            tooltip: 'Archive',
            icon: const Icon(Icons.archive_outlined),
            onPressed: onArchive,
          ),
        ],
      ),
    );
  }
}

/// what the dialog hands back, null if cancelled
class _MenuItemFormResult {
  const _MenuItemFormResult(this.name, this.price, this.isIngredientTracked);
  final String name;
  final double price;
  final bool isIngredientTracked;
}

/// add/edit dialog, pass existing to prefill for edit
class _MenuItemFormDialog extends StatefulWidget {
  const _MenuItemFormDialog({this.existing});

  final MenuItem? existing;

  @override
  State<_MenuItemFormDialog> createState() => _MenuItemFormDialogState();
}

class _MenuItemFormDialogState extends State<_MenuItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late final _priceCtrl = TextEditingController(
    text: widget.existing == null
        ? null
        : quantity(widget.existing!.sellingPrice),
  );
  late bool _isTracked = widget.existing?.isIngredientTracked ?? true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _MenuItemFormResult(
        _nameCtrl.text.trim(),
        double.parse(_priceCtrl.text.trim()),
        _isTracked,
      ),
    );
  }

  // tryParse gives null instead of throwing on bad input like "abc"
  String? _validatePrice(String? v) {
    if (v == null || v.trim().isEmpty) return 'Price is required';
    final parsed = double.tryParse(v.trim());
    if (parsed == null || parsed < 0) return 'Enter a valid price';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit menu item' : 'New menu item'),
      // scroll view so the keyboard can't cause an overflow
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
                  hintText: 'e.g. Iced Latte',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _priceCtrl,
                // decimal: true so the numeric keyboard has a "." key
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Selling price',
                  prefixText: '₱ ',
                ),
                validator: _validatePrice,
                onFieldSubmitted: (_) => _save(),
              ),
              if (isEdit) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Changing the price only affects future sales. Past sales keep '
                  'the price they were rung up at.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              // drinks move stock on every sale, food sold as a whole unit does
              // not, and the app has to be told which this is rather than guess
              // it from whether a recipe happens to exist
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.local_cafe_outlined),
                    label: Text('Made to order'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.bakery_dining_outlined),
                    label: Text('Whole unit'),
                  ),
                ],
                selected: {_isTracked},
                onSelectionChanged: (s) => setState(() => _isTracked = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _isTracked
                    ? 'A drink made from ingredients. It needs a recipe, and '
                        'each sale deducts stock and is counted at closing.'
                    : 'Food sold as it comes, like a pastry. It needs no '
                        'recipe, deducts no stock, and is not part of the '
                        'closing count — but it still appears on receipts and '
                        'in sales records.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                ),
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
