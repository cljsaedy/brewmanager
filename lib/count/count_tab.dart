import 'package:flutter/material.dart';

import '../data/count_line.dart';
import '../data/count_store.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import '../theme/app_theme.dart';
import '../widgets/category_title.dart';
import '../widgets/status_chip.dart';
import 'count_panel.dart';

// badge on the row of an item on its opening count day (rule 3)
const String openingCountBadge = 'Opening count: please count';

// badge on the row of an item at or below its low-stock level, only a mark (rule 8)
const String restockBadge = 'Restock recommended';

// which rows the table shows, the used today filter comes in feature 5 since it needs the tally
enum _CountFilter { all, restock }

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
      if (_filter == _CountFilter.restock && !row.restockRecommended) {
        return false;
      }
      return row.item.name.toLowerCase().contains(search);
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
        hintText: 'Search name',
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

  // shown when the search or the restock filter lets no row through
  Widget _noRowsMessage(BuildContext context) {
    final search = _search.text.trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          search.isEmpty
              ? 'No items need restocking'
              : 'No items match "$search"',
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

  // one logbook row
  // container items show in containers since that is how the barista thinks ("2.75"), rule 1
  // number items show in pcs
  Widget _row(CountRow row) {
    final line = row.line;
    final item = row.item;
    final isContainer = item.countType == CountType.container;

    // a base amount turned into what this row shows, 5500 ml on a 2000 ml bottle = "2.75"
    String shown(double amount) {
      return formatAmount(isContainer ? amount / item.containerSize! : amount);
    }

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
                    if (line.isOpening || row.restockRecommended) ...[
                      const SizedBox(height: 6),
                      _badges(row),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: _unitFlex,
                child: Text(
                  isContainer ? item.containerName : item.baseUnit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: _compact ? 12 : null),
                ),
              ),
              _number(shown(line.startQty)),
              _number(shown(line.inQty)),
              _number(_outText(line, isContainer)),
              _number(shown(line.endQty), bold: true),
            ],
          ),
        ),
      ),
    );
  }

  // the badges under the item name
  // Wrap = they go under each other when the column is narrow
  Widget _badges(CountRow row) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (row.line.isOpening)
          const StatusChip(label: openingCountBadge, tone: ChipTone.warn),
        if (row.restockRecommended)
          const StatusChip(label: restockBadge, tone: ChipTone.warn),
      ],
    );
  }

  // what the Out column shows (rule 3)
  // container items = containers finished
  // number items = pieces used, worked out here and not saved, read only for now
  // an opening count has no usage (rule 7) so it shows a dash, its Start of 0 would give a wrong number
  String _outText(CountLine line, bool isContainer) {
    if (isContainer) return line.outCount.toString();
    if (line.isOpening) return '—';
    return formatAmount(
      amountUsed(start: line.startQty, inQty: line.inQty, end: line.endQty),
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
