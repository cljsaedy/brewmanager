import 'package:flutter/material.dart';

import '../../data/stock_item.dart';
import '../../data/stock_item_store.dart';
import '../../logic/formatting.dart';
import '../../logic/units.dart';
import '../../theme/app_theme.dart';
import 'stock_item_form.dart';

// owner tab that lists every stock item in a table, grouped by category
// add item or tapping a row opens the form panel on the right, archive / restore comes in 2d
class StockItemsTab extends StatefulWidget {
  const StockItemsTab({super.key, required this.store});

  final StockItemStore store;

  @override
  State<StockItemsTab> createState() => _StockItemsTabState();
}

class _StockItemsTabState extends State<StockItemsTab> {
  // null while still loading from the db
  List<StockItem>? _items;
  // categories already used, passed to the form for the chips
  List<String> _categories = [];

  // true while the form panel is showing
  bool _panelOpen = false;
  // the item being edited, null = adding a new one
  StockItem? _editing;

  // width of the form panel, the table gets the rest
  static const double _panelWidth = 340;

  // how wide each column is compared to the others (flex), header and rows use the same ones
  static const int _nameFlex = 4;
  static const int _unitFlex = 1;
  static const int _typeFlex = 2;
  static const int _containerFlex = 3;
  static const int _lowFlex = 3;

  // while the panel is open the table is too narrow for every column, so only name + unit show
  bool get _compact => _panelOpen;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // reads the active items and categories from the db, then redraws
  Future<void> _load() async {
    final items = await widget.store.list();
    final categories = await widget.store.categories();
    // mounted = the tab is still on screen (the owner could have locked while loading)
    if (!mounted) return;
    setState(() {
      _items = items;
      _categories = categories;
    });
  }

  void _openAdd() {
    setState(() {
      _editing = null;
      _panelOpen = true;
    });
  }

  void _openEdit(StockItem item) {
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

  // after a save or restore: close the panel, show the message at the bottom, reload the list
  void _onFormDone(String message) {
    _closePanel();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _tableCard(context)),
        if (_panelOpen) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: _panelWidth,
            child: StockItemForm(
              // a new key per item = the form starts fresh when another row is tapped
              key: ValueKey(_editing?.id ?? 'new'),
              store: widget.store,
              item: _editing,
              categories: _categories,
              onDone: _onFormDone,
              onCancel: _closePanel,
            ),
          ),
        ],
      ],
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
          _columnTitles(context),
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

  // title, item count, and the add button
  Widget _header(BuildContext context, List<StockItem>? items) {
    final text = Theme.of(context).textTheme;
    final count = items?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stock Items', style: text.headlineSmall),
                const SizedBox(height: 2),
                Text(
                  count == 1 ? '1 item' : '$count items',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _openAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add item'),
          ),
        ],
      ),
    );
  }

  // the light cream strip with the column names
  Widget _columnTitles(BuildContext context) {
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
          const Expanded(
            flex: _unitFlex,
            child: Text('Unit', style: style),
          ),
          if (!_compact) ...const [
            Expanded(
              flex: _typeFlex,
              child: Text('Count type', style: style),
            ),
            Expanded(
              flex: _containerFlex,
              child: Text('Container', style: style),
            ),
            Expanded(
              flex: _lowFlex,
              child: Text('Low-stock level', style: style),
            ),
          ],
        ],
      ),
    );
  }

  // shown when there are no stock items yet
  Widget _emptyMessage(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 10),
          Text('No stock items yet', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Add the things your cafe counts, like milk, syrups and cups.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  // the rows, with a category title above each group
  // items already come sorted by category, so a new title goes in whenever the category changes
  Widget _table(List<StockItem> items) {
    final rows = <Widget>[];
    String? lastCategory;

    for (final item in items) {
      // compare in lowercase so "Syrups" and "syrups" end up in one group
      final category = item.category.toLowerCase();
      if (category != lastCategory) {
        rows.add(_CategoryTitle(item.category));
        lastCategory = category;
      }
      rows.add(_row(item));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: rows,
    );
  }

  // one stock item row
  Widget _row(StockItem item) {
    final unit = item.baseUnit.name;
    final isContainer = item.countType == CountType.container;
    // 'container' when the owner left the container name empty
    final label = item.containerName;

    // container column, like "bottle · 2,000 ml", number items have no container
    final container = isContainer
        ? '$label · ${formatWithUnit(item.containerSize ?? 0, unit)}'
        : '—';

    // low-stock level in the mode the owner picked, like "1 bottle" or "500 g"
    final low = item.lowMode == LowMode.containers
        ? formatContainers(item.lowValue, label)
        : formatWithUnit(item.lowValue, unit);

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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(flex: _unitFlex, child: Text(unit)),
              if (!_compact) ...[
                Expanded(
                  flex: _typeFlex,
                  child: Text(isContainer ? 'Container' : 'Number'),
                ),
                Expanded(
                  flex: _containerFlex,
                  child: Text(container, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  flex: _lowFlex,
                  child: Text(low, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// small caramel title above each category group, like "SYRUPS"
class _CategoryTitle extends StatelessWidget {
  const _CategoryTitle(this.category);

  final String category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        category.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.caramel,
        ),
      ),
    );
  }
}
