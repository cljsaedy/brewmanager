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

  // width of the panel, the table gets the rest
  static const double _panelWidth = 340;

  // how wide each column is compared to the others (flex), header and rows use the same ones
  static const int _nameFlex = 6;
  static const int _unitFlex = 2;
  static const int _numberFlex = 2;

  // the row of the open panel, null if nothing is selected or the item is gone
  CountRow? get _selectedRow {
    for (final row in widget.draft?.rows ?? const <CountRow>[]) {
      if (row.item.id == _selectedItemId) return row;
    }
    return null;
  }

  // while the panel is open the table is too narrow for the unit, the panel shows it anyway
  bool get _compact => _selectedRow != null;

  void _select(int? itemId) {
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

  Widget _tableCard(BuildContext context) {
    final rows = widget.draft?.rows;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, rows),
          const SizedBox(height: 4),
          _columnTitles(),
          // Expanded = the list gets all the height left in the card and scrolls inside it
          Expanded(
            child: rows == null
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? _emptyMessage(context)
                : _table(rows),
          ),
        ],
      ),
    );
  }

  // title and item count
  Widget _header(BuildContext context, List<CountRow>? rows) {
    final text = Theme.of(context).textTheme;
    final count = rows?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Logbook', style: text.headlineSmall),
          const SizedBox(height: 2),
          Text(count == 1 ? '1 item' : '$count items', style: text.bodySmall),
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
          const Expanded(
            flex: _nameFlex,
            child: Text('Name', style: style),
          ),
          if (!_compact)
            const Expanded(
              flex: _unitFlex,
              child: Text('Unit', style: style),
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
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (line.isOpening) ...const [
                      SizedBox(height: 6),
                      StatusChip(label: openingCountBadge, tone: ChipTone.warn),
                    ],
                  ],
                ),
              ),
              if (!_compact)
                Expanded(
                  flex: _unitFlex,
                  child: Text(
                    isContainer ? item.containerName : item.baseUnit.name,
                    overflow: TextOverflow.ellipsis,
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
