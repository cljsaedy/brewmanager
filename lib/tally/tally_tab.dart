import 'package:flutter/material.dart';

import '../data/menu_item.dart';
import '../data/tally_store.dart';
import '../logic/formatting.dart';
import '../theme/app_theme.dart';
import '../widgets/category_title.dart';

// the barista's tally: tap a menu item each time one is made
// left = menu grid by category, right = today's list with - and + to fix mistakes
// the grid can only add, so a stray tap there can never lower a number
class TallyTab extends StatefulWidget {
  const TallyTab({super.key, required this.dayId, required this.store});

  // these 2 are null while still loading from the db
  final int? dayId;
  final TallyStore? store;

  @override
  State<TallyTab> createState() => _TallyTabState();
}

class _TallyTabState extends State<TallyTab> {
  // width of the list on the right, the grid gets the rest
  static const double _listWidth = 280;

  // the most width one tile can take, the grid fits as many across as it can
  static const double _tileMaxWidth = 200;
  static const double _tileHeight = 84;

  // the menu items, null while loading
  List<MenuItem>? _items;

  // menu item id -> how many today
  // kept here so every tap shows at once, the db saves the same +1 or -1 behind it
  final Map<int, int> _quantities = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = widget.store;
    final dayId = widget.dayId;
    if (store == null || dayId == null) return;

    final rows = await store.load(dayId);
    // mounted = this screen is still open
    if (!mounted) return;
    setState(() {
      _items = rows.map((row) => row.item).toList();
      for (final row in rows) {
        _quantities[row.item.id!] = row.qty;
      }
    });
  }

  int _qty(MenuItem item) => _quantities[item.id!] ?? 0;

  Future<void> _add(MenuItem item) async {
    setState(() => _quantities[item.id!] = _qty(item) + 1);
    await widget.store!.add(widget.dayId!, item.id!);
  }

  Future<void> _remove(MenuItem item) async {
    if (_qty(item) == 0) return;

    setState(() => _quantities[item.id!] = _qty(item) - 1);
    await widget.store!.remove(widget.dayId!, item.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Card(child: _menuSide(context))),
        const SizedBox(width: 12),
        SizedBox(
          width: _listWidth,
          child: Card(child: _listSide(context)),
        ),
      ],
    );
  }

  // the left side: loading, a message, or the grid
  Widget _menuSide(BuildContext context) {
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());

    // an archived item stays in today's list but cant be picked from the menu anymore
    final active = items.where((item) => !item.isArchived).toList();
    if (active.isEmpty) return _emptyMessage(context);

    return _grid(active);
  }

  // shown when the owner has not added any menu items yet
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
          Text('No menu items yet', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The owner adds them in the owner section.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  // one small grid per category with its title above it
  // items already come sorted by category, a new group starts whenever the category changes
  Widget _grid(List<MenuItem> items) {
    final groups = <List<MenuItem>>[];
    String? lastCategory;

    for (final item in items) {
      // compare in lowercase so "Coffee" and "coffee" end up in one group
      final category = item.category.toLowerCase();
      if (category != lastCategory) {
        groups.add([]);
        lastCategory = category;
      }
      groups.last.add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        for (final group in groups) ...[
          CategoryTitle(group.first.category),
          // shrinkWrap + no scroll = the grid is only as tall as its tiles, the ListView does the scrolling
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _tileMaxWidth,
              mainAxisExtent: _tileHeight,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            children: [for (final item in group) _tile(item)],
          ),
        ],
      ],
    );
  }

  // one menu item, a tap adds 1
  // the price is only a hint to pick the right item, it never gets saved or added up
  Widget _tile(MenuItem item) {
    final qty = _qty(item);
    final price = item.priceHint;

    // Material + InkWell = tap ripple, a tile with a quantity gets a cream background
    return Material(
      color: qty > 0 ? AppColors.cream : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        side: const BorderSide(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('tally_tile_${item.id}'),
        onTap: () => _add(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (price != null)
                      Text(
                        formatAmount(price),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (qty > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$qty',
                  key: Key('tally_count_${item.id}'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.caramel,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // the right side: today's list
  Widget _listSide(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tallied = (_items ?? const <MenuItem>[])
        .where((item) => _qty(item) > 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Text("Today's tally", style: text.titleMedium),
        ),
        const Divider(),
        Expanded(
          child: tallied.isEmpty
              ? Center(
                  child: Text('Nothing tallied yet', style: text.bodySmall),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [for (final item in tallied) _listRow(item)],
                ),
        ),
      ],
    );
  }

  // one line of today's list, like "Iced Americano (Large) × 2" with - and +
  Widget _listRow(MenuItem item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 8, 2),
      child: Row(
        children: [
          Expanded(child: Text('${item.name} × ${_qty(item)}')),
          IconButton(
            key: Key('tally_minus_${item.id}'),
            tooltip: 'Remove one',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => _remove(item),
          ),
          IconButton(
            key: Key('tally_plus_${item.id}'),
            tooltip: 'Add one',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _add(item),
          ),
        ],
      ),
    );
  }
}
