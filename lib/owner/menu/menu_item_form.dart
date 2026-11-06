import 'package:flutter/material.dart';

import '../../data/menu_item.dart';
import '../../data/menu_item_store.dart';
import '../../data/recipe_store.dart';
import '../../data/stock_item.dart';
import '../../data/stock_item_store.dart';
import '../../logic/formatting.dart';
import '../../widgets/message_box.dart';
import 'recipe_editor.dart';

// the right side panel for adding a new menu item or editing one, with its recipe under the fields
// item null = adding a new one
class MenuItemForm extends StatefulWidget {
  const MenuItemForm({
    super.key,
    required this.store,
    required this.recipes,
    required this.stock,
    required this.item,
    required this.categories,
    required this.onDone,
    required this.onSavedForRecipe,
    required this.onRecipeChanged,
    required this.onCancel,
  });

  final MenuItemStore store;
  final RecipeStore recipes;
  final StockItemStore stock;
  final MenuItem? item;
  // categories already used, shown as tap-to-fill chips
  final List<String> categories;
  // called after saving or restoring, with the message for the snackbar
  final ValueChanged<String> onDone;
  // called instead of onDone when the save made the recipe part usable,
  // gives the saved item so the panel can stay open on it
  final void Function(MenuItem saved, String message) onSavedForRecipe;
  // called after a recipe line changed, so the table can show the new count
  final VoidCallback onRecipeChanged;
  final VoidCallback onCancel;

  @override
  State<MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends State<MenuItemForm> {
  // text boxes
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();

  // the "not compared" checkbox
  bool _noStock = false;
  // true when the item has recipe lines, then the checkbox cant be ticked (rule 6)
  bool _hasRecipe = false;

  String? _error;
  // set when the typed name belongs to an archived item, shows the restore offer
  MenuItem? _archivedMatch;
  // stops a double tap saving twice
  bool _saving = false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item == null) return;

    // editing: fill the boxes with the saved values
    _nameController.text = item.name;
    _categoryController.text = item.category;
    if (item.priceHint != null) {
      _priceController.text = plainNumber(item.priceHint!);
    }
    _noStock = item.noStock;
    _checkRecipe(item.id!);
  }

  // asks the db if the item has recipe lines, then greys out the checkbox if it does
  Future<void> _checkRecipe(int id) async {
    final count = await widget.store.activeLineCount(id);
    if (!mounted) return;
    setState(() => _hasRecipe = count > 0);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // reads all boxes into a MenuItem, or sets _error and gives back null if the price is wrong
  MenuItem? _buildItem() {
    // empty price box = no price, it is optional
    final priceText = _priceController.text.trim();
    double? price;
    if (priceText.isNotEmpty) {
      price = readNumber(priceText);
      if (price == null) {
        setState(() => _error = 'Type the price as a number.');
        return null;
      }
    }

    return MenuItem(
      id: widget.item?.id,
      name: _nameController.text,
      category: _categoryController.text,
      priceHint: price,
      noStock: _noStock,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _archivedMatch = null;
    });

    final item = _buildItem();
    if (item == null) return;

    // same rule check the store does, but shown here before touching the db
    final problem = menuItemProblem(item);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() => _saving = true);
    try {
      // the recipe part was not usable before this save: a new item has no id for the lines yet,
      // and a saved no-stock item cant have lines
      final recipeWasClosed = _isNew || widget.item!.noStock;
      if (_isNew) {
        await widget.store.add(item);
      } else {
        await widget.store.update(item);
      }

      final message = 'Saved ${item.name.trim()}.';
      if (recipeWasClosed && !item.noStock) {
        // read it back so the panel gets the saved row, with its id and cleaned up category
        final saved = await widget.store.findByName(item.name);
        widget.onSavedForRecipe(saved!, message);
      } else {
        widget.onDone(message);
      }
    } on MenuNameTakenException catch (e) {
      // archived item with this name: offer restore instead of a duplicate (rule 12)
      setState(() {
        if (e.existing.isArchived) {
          _archivedMatch = e.existing;
        } else {
          _error = 'Another menu item is already called "${e.existing.name}".';
        }
      });
    } on MenuItemException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // brings back the archived item with its old recipe, what was typed here is dropped
  // recipe lines whose stock item got archived meanwhile are left out, the message says which
  Future<void> _restoreMatch() async {
    final match = _archivedMatch!;
    final leftOut = await widget.store.restore(match.id!);
    final note = leftOut.isEmpty
        ? ''
        : ' Left out archived stock items: ${leftOut.join(', ')}.';
    widget.onDone('Restored ${match.name}.$note');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // title + close
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isNew ? 'Add menu item' : 'Edit menu item',
                    style: text.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const Divider(),
          // the fields scroll, so the keyboard or a short screen never cuts them off
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('menu_name_field'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      // each size is its own menu item (rule 6)
                      hintText: 'like Iced Americano (Large)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _categoryField(),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('menu_price_field'),
                    controller: _priceController,
                    // number keyboard with a dot for decimals
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Price (optional)',
                      helperText: 'Only shown in the tally to help pick.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _noStockBox(text),
                  _recipeSection(text),
                ],
              ),
            ),
          ),
          // error / restore offer sit outside the scrolling list, right above save,
          // so the owner always sees them after tapping save
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: MessageBox(text: _error!, isError: true),
            ),
          if (_archivedMatch != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _restoreOffer(),
            ),
          const Divider(),
          // cancel + save at the bottom, always visible
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // category box + chips of the categories already used
  Widget _categoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('menu_category_field'),
          controller: _categoryController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category (optional)',
            hintText: 'empty = $defaultCategory',
          ),
        ),
        if (widget.categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Wrap = chips go to the next line when they dont fit
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final category in widget.categories)
                ActionChip(
                  label: Text(category),
                  onPressed: () =>
                      setState(() => _categoryController.text = category),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // "not compared" checkbox (no_stock in the db), for things like hot water,
  // or food made from batter since prep recipes are not modeled
  // these items never show as "no recipe yet" (rule 6)
  // greyed out while the item has recipe lines, so lines never get dropped by a tick
  Widget _noStockBox(TextTheme text) {
    // a ticked box stays untickable even with lines, so a wrong state can still be fixed
    final canChange = !_hasRecipe || _noStock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: const Key('no_stock_box'),
          value: _noStock,
          // onChanged null = the checkbox is greyed out
          onChanged: canChange
              ? (ticked) => setState(() => _noStock = ticked ?? false)
              : null,
          title: const Text('Not compared (no recipe needed)'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        if (!canChange)
          Text(
            'Remove the recipe lines first to tick this.',
            style: text.bodySmall,
          ),
      ],
    );
  }

  // the recipe under the fields
  // nothing shows while the box is ticked, the item uses no stock
  // new items and saved no-stock items need a save first, the store would refuse their lines
  Widget _recipeSection(TextTheme text) {
    final item = widget.item;
    if (_noStock) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 12),
        if (item == null || item.noStock)
          Text('Save this item to add its recipe.', style: text.bodySmall)
        else
          RecipeEditor(
            recipes: widget.recipes,
            stock: widget.stock,
            menuItemId: item.id!,
            onChanged: (lineCount) {
              // the no-stock box follows the recipe, greyed out once it has lines
              setState(() => _hasRecipe = lineCount > 0);
              widget.onRecipeChanged();
            },
          ),
      ],
    );
  }

  // yellow box: an archived item already has this name, restore it?
  Widget _restoreOffer() {
    final match = _archivedMatch!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessageBox(
          text:
              '"${match.name}" is an archived menu item. Restore it with its '
              'old recipe instead of adding a new one?',
          isError: false,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _restoreMatch,
            icon: const Icon(Icons.unarchive_outlined, size: 18),
            label: const Text('Restore it'),
          ),
        ),
      ],
    );
  }
}
