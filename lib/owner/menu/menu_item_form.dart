import 'package:flutter/material.dart';

import '../../data/menu_item.dart';
import '../../data/menu_item_store.dart';
import '../../data/stock_item.dart';
import '../../logic/formatting.dart';
import '../../widgets/message_box.dart';

// the right side panel for adding a new menu item or editing one
// item null = adding a new one
// the recipe editor goes in this panel later (3d)
class MenuItemForm extends StatefulWidget {
  const MenuItemForm({
    super.key,
    required this.store,
    required this.item,
    required this.categories,
    required this.onDone,
    required this.onCancel,
  });

  final MenuItemStore store;
  final MenuItem? item;
  // categories already used, shown as tap-to-fill chips
  final List<String> categories;
  // called after saving or restoring, with the message for the snackbar
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  State<MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends State<MenuItemForm> {
  // text boxes
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();

  // the "doesn't use tracked stock" checkbox
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
      if (_isNew) {
        await widget.store.add(item);
      } else {
        await widget.store.update(item);
      }
      widget.onDone('Saved ${item.name.trim()}.');
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

  // "doesn't use tracked stock" checkbox, for things like hot water or a service charge
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
          title: const Text("Doesn't use tracked stock"),
          subtitle: const Text('It never shows as "no recipe yet".'),
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
