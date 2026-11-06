import 'package:flutter/material.dart';

import '../data/count_line.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import '../theme/app_theme.dart';
import '../widgets/category_title.dart';
import '../widgets/status_chip.dart';

// badge on the row of an item on its opening count day (rule 3)
const String openingCountBadge = 'Opening count: please count';

// the barista's logbook: one row per stock item, grouped by category
// the app layout loads the draft and passes it here since the top bar needs the same date
class CountTab extends StatelessWidget {
  const CountTab({super.key, required this.draft});

  // null while still loading from the db
  final DraftDay? draft;

  // how wide each column is compared to the others (flex), header and rows use the same ones
  static const int _nameFlex = 6;
  static const int _unitFlex = 2;
  static const int _numberFlex = 2;

  @override
  Widget build(BuildContext context) {
    final rows = draft?.rows;

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

    return Container(
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
