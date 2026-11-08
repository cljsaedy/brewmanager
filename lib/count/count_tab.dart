import 'package:flutter/material.dart';

import '../data/count_line.dart';
import '../data/count_store.dart';
import '../theme/app_theme.dart';
import '../widgets/category_title.dart';
import 'count_badges.dart';
import 'count_cells.dart';
import 'count_panel.dart';

// which rows the table shows
enum _CountFilter { all, usedToday, restock }

// the barista's logbook: one row per stock item, grouped by category
// the app layout loads the draft and passes it here since the top bar needs the same date
// tapping a row opens that item's panel on the right
class CountTab extends StatefulWidget {
  const CountTab({
    super.key,
    required this.draft,
    required this.store,
    required this.onChanged,
  });

  // these 2 are null while still loading from the db
  final DraftDay? draft;
  final CountStore? store;
  // called after every save, the app layout reads the draft again
  final VoidCallback onChanged;

  @override
  State<CountTab> createState() => _CountTabState();
}

class _CountTabState extends State<CountTab> {
  // the stock item of the open panel, null = no panel
  // the id and not the row, since the rows get replaced on every reload
  int? _selectedItemId;

  _CountFilter _filter = _CountFilter.all;

  // the text in the search box and whether the box has the keyboard
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // width of the panel, the table gets the rest
  static const double _panelWidth = 340;

  // below this height the keyboard is open, then the title and filters hide so the rows still fit
  static const double _minHeightForHeader = 240;

  // the search box stays small, the title gets the rest of the row
  static const double _searchWidth = 180;

  // how wide each column is compared to the others (flex), header and rows use the same ones
  // the numbers get a bigger share while the panel is open since the table is much narrower then
  int get _nameFlex => _compact ? 8 : 6;
  int get _unitFlex => _compact ? 6 : 2;
  int get _numberFlex => _compact ? 4 : 2;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // the row of the open panel, null if nothing is selected or the item is gone
  CountRow? get _selectedRow {
    for (final row in widget.draft?.rows ?? const <CountRow>[]) {
      if (row.item.id == _selectedItemId) return row;
    }
    return null;
  }

  // while the panel is open the table is narrow, so the columns change to still fit the unit
  bool get _compact => _selectedRow != null;

  void _select(int? itemId) {
    // closes the keyboard from searching, or it would cover the panel that just opened
    _searchFocus.unfocus();
    setState(() => _selectedItemId = itemId);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRow;
    final store = widget.store;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _tableCard(context)),
        if (selected != null && store != null) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: _panelWidth,
            child: CountPanel(
              // a new key per line = the panel starts fresh when another row is tapped
              key: ValueKey(selected.line.id),
              store: store,
              row: selected,
              onChanged: widget.onChanged,
              onClose: () => _select(null),
            ),
          ),
        ],
      ],
    );
  }

  // the rows the filter and the search both let through
  // an open panel stays open even if its row leaves the list here, it is found in all the rows
  List<CountRow> _filtered(List<CountRow> rows) {
    final search = _search.text.trim().toLowerCase();

    return rows.where((row) {
      // the used today filter keeps touched items too, so the barista can go back over them
      final passesFilter = switch (_filter) {
        _CountFilter.all => true,
        _CountFilter.usedToday => row.usedToday,
        _CountFilter.restock => row.restockRecommended,
      };
      return passesFilter && row.item.name.toLowerCase().contains(search);
    }).toList();
  }

  // what goes in the card under the column names
  Widget _tableBody(BuildContext context, List<CountRow>? rows) {
    if (rows == null) return const Center(child: CircularProgressIndicator());
    if (rows.isEmpty) return _emptyMessage(context);

    final shown = _filtered(rows);
    return shown.isEmpty ? _noRowsMessage(context) : _table(shown);
  }

  Widget _tableCard(BuildContext context) {
    final rows = widget.draft?.rows;

    // LayoutBuilder = tells how much height the card really gets right now
    return LayoutBuilder(
      builder: (context, size) {
        final isTall = size.maxHeight >= _minHeightForHeader;

        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, rows, showTitle: isTall),
              if (isTall) ...[_filters(), const SizedBox(height: 4)],
              _columnTitles(),
              // Expanded = the list gets all the height left in the card and scrolls inside it
              Expanded(child: _tableBody(context, rows)),
            ],
          ),
        );
      },
    );
  }

  // title, item count and the search box
  // the search box stays when the keyboard opens, if it hid it would lose the keyboard while typing
  Widget _header(
    BuildContext context,
    List<CountRow>? rows, {
    required bool showTitle,
  }) {
    final text = Theme.of(context).textTheme;
    final count = rows?.length ?? 0;

    return Padding(
      padding: showTitle
          ? const EdgeInsets.fromLTRB(24, 20, 20, 12)
          : const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          // the title takes the space on the left, this keeps the search box on the right
          if (showTitle)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Logbook', style: text.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    count == 1 ? '1 item' : '$count items',
                    style: text.bodySmall,
                  ),
                ],
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 16),
          // the key keeps this the same box when the title leaves the row, so typing isnt lost
          SizedBox(
            key: const Key('search_area'),
            width: _searchWidth,
            child: _searchBox(),
          ),
        ],
      ),
    );
  }

  // finds items by name, only the words typed here, nothing gets saved
  Widget _searchBox() {
    return TextField(
      key: const Key('count_search'),
      controller: _search,
      focusNode: _searchFocus,
      textInputAction: TextInputAction.search,
      // redraws the table on every letter
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        // a widget hint instead of hintText so it can shrink to fit a narrow box instead of ending with "..."
        // a widget hint doesnt get the grey hint color by itself, so it is set here from the theme
        hint: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Search name',
            maxLines: 1,
            style:
                Theme.of(context).inputDecorationTheme.hintStyle ??
                TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                key: const Key('count_search_clear'),
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_search.clear),
              ),
      ),
    );
  }

  // the filter buttons, Wrap = they go to the next line if the table is narrow
  Widget _filters() {
    Widget chip(Key key, String label, _CountFilter filter) {
      return ChoiceChip(
        key: key,
        label: Text(label),
        selected: _filter == filter,
        showCheckmark: false,
        selectedColor: AppColors.cream,
        onSelected: (_) => setState(() => _filter = filter),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 20, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(const Key('filter_all'), 'All', _CountFilter.all),
          chip(const Key('filter_used'), 'Used Today', _CountFilter.usedToday),
          chip(const Key('filter_restock'), restockBadge, _CountFilter.restock),
        ],
      ),
    );
  }

  // the light cream strip with the column names, the labels are fixed by rule 3
  Widget _columnTitles() {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    );

    Widget number(String label) {
      return Expanded(
        flex: _numberFlex,
        child: Text(label, textAlign: TextAlign.right, style: style),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _nameFlex,
            child: const Text('Name', style: style),
          ),
          Expanded(
            flex: _unitFlex,
            child: const Text('Unit', style: style),
          ),
          number('Start'),
          number('In'),
          number('Out'),
          number('End'),
        ],
      ),
    );
  }

  // shown when the owner has not added any stock items yet
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
            'The owner adds them in the owner section.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  // what to say when the search or a filter lets no row through
  String _noRowsText() {
    final search = _search.text.trim();
    if (search.isNotEmpty) return 'No items match "$search"';

    return _filter == _CountFilter.usedToday
        ? 'No items used today'
        : 'No items need restocking';
  }

  Widget _noRowsMessage(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _noRowsText(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  // the rows with a category title above each group
  // rows already come sorted by category, so a new title goes in whenever the category changes
  Widget _table(List<CountRow> rows) {
    final children = <Widget>[];
    String? lastCategory;

    for (final row in rows) {
      // compare in lowercase so "Syrups" and "syrups" end up in one group
      final category = row.item.category.toLowerCase();
      if (category != lastCategory) {
        children.add(CategoryTitle(row.item.category));
        lastCategory = category;
      }
      children.add(_row(row));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: children,
    );
  }

  // one logbook row, count_cells.dart decides what each cell says
  Widget _row(CountRow row) {
    final line = row.line;
    final item = row.item;

    // Material + InkWell = tap ripple, the open row gets a cream background
    return Material(
      color: item.id == _selectedItemId ? AppColors.cream : Colors.transparent,
      child: InkWell(
        onTap: () => _select(item.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: _nameFlex,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (!_compact && row.hasBadges) ...[
                      const SizedBox(height: 6),
                      CountBadges(row),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: _unitFlex,
                // 2 lines when the panel makes it narrow
                child: Text(
                  unitText(item),
                  maxLines: _compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: _compact ? 12 : null),
                ),
              ),
              _number(shownAmount(item, line.startQty)),
              _number(shownAmount(item, line.inQty)),
              _number(outText(item, line)),
              _number(shownAmount(item, line.endQty), bold: true),
            ],
          ),
        ),
      ),
    );
  }

  // one number cell, right aligned so the digits line up under the title
  Widget _number(String value, {bool bold = false}) {
    return Expanded(
      flex: _numberFlex,
      child: Text(
        value,
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: bold ? FontWeight.w600 : null),
      ),
    );
  }
}
