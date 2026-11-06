import 'package:flutter/material.dart';

import '../../data/menu_item.dart';
import '../../data/menu_item_store.dart';
import '../../data/recipe_store.dart';
import '../../data/stock_item_store.dart';
import '../../logic/formatting.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_title.dart';
import '../../widgets/status_chip.dart';
import 'archived_menu_panel.dart';
import 'menu_item_form.dart';

// owner tab that lists every menu item in a table, grouped by category
// every size is its own menu item, like "Iced Americano (Large)" (rule 6)
// add item or tapping a row opens the form panel on the right
// the active / archived switch shows archived items, tapping one opens a read only panel with restore
class MenuTab extends StatefulWidget {
  const MenuTab({
    super.key,
    required this.store,
    required this.recipes,
    required this.stock,
  });

  final MenuItemStore store;
  final RecipeStore recipes;
  // the recipe editor picks from the active stock items
  final StockItemStore stock;

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  // null while still loading from the db
  List<MenuItem>? _items;
  // active recipe line count per menu item id, items not in it have no recipe yet
  Map<int, int> _lineCounts = {};
  // categories already used, passed to the form for the chips
  List<String> _categories = [];

  // true while the form panel is showing
  bool _panelOpen = false;
  // the item being edited, null = adding a new one
  MenuItem? _editing;
  // false = active items, true = archived items
  bool _showArchived = false;

  // width of the form panel, same as the stock items tab
  static const double _panelWidth = 340;

  // how wide each column is compared to the others (flex), header and rows use the same ones
  static const int _nameFlex = 5;
  static const int _priceFlex = 2;
  static const int _recipeFlex = 3;

  // while the panel is open the table is too narrow, so the price column is hidden
  bool get _compact => _panelOpen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // reads the active (or archived) items, their recipe line counts and the categories from the db, then redraws
  // categories always come from active items, they are only for the form chips
  Future<void> _load() async {
    final items = await widget.store.list(archived: _showArchived);
    final lineCounts = await widget.store.lineCounts();
    final categories = await widget.store.categories();
    // mounted = the tab is still on screen (the owner could have locked while loading)
    if (!mounted) return;
    setState(() {
      _items = items;
      _lineCounts = lineCounts;
      _categories = categories;
    });
  }

  void _openAdd() {
    setState(() {
      _editing = null;
      _panelOpen = true;
    });
  }

  void _openEdit(MenuItem item) {
    setState(() {
      _editing = item;
      _panelOpen = true;
    });
  }

  void _closePanel() {
    setState(() {
      _panelOpen = false;
      _editing = null;
    });
  }

  // switching active / archived closes the panel and loads the other list
  void _setShowArchived(bool archived) {
    setState(() {
      _showArchived = archived;
      _panelOpen = false;
      _editing = null;
      // null = shows the loading circle until the other list is read
      _items = null;
    });
    _load();
  }

  // after a save, archive or restore: close the panel, show the message at the bottom, reload the list
  void _onFormDone(String message) {
    _closePanel();
    _showMessage(message);
    _load();
  }

  // after saving a new item: the panel stays open on it, so the owner can add its recipe next
  void _onSavedForRecipe(MenuItem saved, String message) {
    _openEdit(saved);
    _showMessage(message);
    _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _tableCard(context)),
        if (_panelOpen) ...[
          const SizedBox(width: 12),
          SizedBox(width: _panelWidth, child: _panel()),
        ],
      ],
    );
  }

  // archived item = read only panel with restore, otherwise the add / edit form
  Widget _panel() {
    final editing = _editing;
    if (editing != null && editing.isArchived) {
      return ArchivedMenuPanel(
        // a new key per item = the panel starts fresh when another row is tapped
        key: ValueKey('archived-${editing.id}'),
        store: widget.store,
        item: editing,
        onDone: _onFormDone,
        onCancel: _closePanel,
      );
    }
    return MenuItemForm(
      // a new key per item = the form starts fresh when another row is tapped
      key: ValueKey(editing?.id ?? 'new'),
      store: widget.store,
      recipes: widget.recipes,
      stock: widget.stock,
      item: editing,
      categories: _categories,
      onDone: _onFormDone,
      onSavedForRecipe: _onSavedForRecipe,
      // recipes save right away, so only the table needs a redraw
      onRecipeChanged: _load,
      onCancel: _closePanel,
    );
  }

  Widget _tableCard(BuildContext context) {
    final items = _items;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, items),
          const SizedBox(height: 4),
          _columnTitles(),
          // Expanded = the list gets all the height left in the card and scrolls inside it
          Expanded(
            child: items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? _emptyMessage(context)
                : _table(items),
          ),
        ],
      ),
    );
  }

  // title, item count, the active / archived switch, and the add button
  Widget _header(BuildContext context, List<MenuItem>? items) {
    final text = Theme.of(context).textTheme;
    final count = items?.length ?? 0;
    final countText = _showArchived
        ? '$count archived'
        : (count == 1 ? '1 menu item' : '$count menu items');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Menu & Recipes', style: text.headlineSmall),
                const SizedBox(height: 2),
                Text(countText, style: text.bodySmall),
              ],
            ),
          ),
          // the switch is hidden while the panel is open, the table is too narrow for it then
          if (!_compact)
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Active')),
                ButtonSegment(value: true, label: Text('Archived')),
              ],
              selected: {_showArchived},
              onSelectionChanged: (picked) => _setShowArchived(picked.first),
            ),
          // archived items cant be added, only restored
          if (!_showArchived) ...[
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _openAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add item'),
            ),
          ],
        ],
      ),
    );
  }

  // the light cream strip with the column names
  Widget _columnTitles() {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        children: [
          const Expanded(
            flex: _nameFlex,
            child: Text('Name', style: style),
          ),
          if (!_compact)
            const Expanded(
              flex: _priceFlex,
              child: Text('Price', style: style),
            ),
          // archived items have no active lines, every row would wrongly say no recipe yet
          if (!_showArchived)
            const Expanded(
              flex: _recipeFlex,
              child: Text('Recipe', style: style),
            ),
        ],
      ),
    );
  }

  // shown when there are no menu items yet
  Widget _emptyMessage(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.restaurant_menu,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 10),
          Text(
            _showArchived ? 'No archived items' : 'No menu items yet',
            style: text.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _showArchived
                ? 'Items you archive show up here, so you can restore them.'
                : 'Add what the cafe sells. Each size is its own item, '
                      'like "Iced Americano (Large)".',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  // the rows, with a category title above each group
  // items already come sorted by category, so a new title goes in whenever the category changes
  Widget _table(List<MenuItem> items) {
    final rows = <Widget>[];
    String? lastCategory;

    for (final item in items) {
      // compare in lowercase so "Coffee" and "coffee" end up in one group
      final category = item.category.toLowerCase();
      if (category != lastCategory) {
        rows.add(CategoryTitle(item.category));
        lastCategory = category;
      }
      rows.add(_row(item));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: rows,
    );
  }

  // one menu item row
  Widget _row(MenuItem item) {
    final price = item.priceHint;
    // the row being edited gets a cream background so the owner sees which one is open
    final selected = _panelOpen && _editing?.id == item.id;

    // Material + InkWell = tap ripple, tapping opens the edit panel
    return Material(
      color: selected ? AppColors.cream : Colors.transparent,
      child: InkWell(
        onTap: () => _openEdit(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: _nameFlex,
                child: Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  // archived names are a bit greyed so the view looks different
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: item.isArchived ? AppColors.textMuted : null,
                  ),
                ),
              ),
              if (!_compact)
                Expanded(
                  flex: _priceFlex,
                  // no currency sign, the price is only a hint for the tally
                  child: Text(price == null ? '—' : formatAmount(price)),
                ),
              if (!_showArchived)
                Expanded(
                  flex: _recipeFlex,
                  // Align = the chip keeps its own width instead of stretching
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _recipeStatus(item),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // what the recipe column says:
  // "Not compared" for no-stock items, "2 stock items" when it has a recipe,
  // an amber "No recipe yet" chip otherwise, so the owner sees what is left to set up
  Widget _recipeStatus(MenuItem item) {
    if (item.noStock) {
      return const Text(
        'Not compared',
        style: TextStyle(color: AppColors.textMuted),
      );
    }
    final count = _lineCounts[item.id] ?? 0;
    if (count == 0) {
      return const StatusChip(label: 'No recipe yet', tone: ChipTone.warn);
    }
    return Text(count == 1 ? '1 stock item' : '$count stock items');
  }
}
