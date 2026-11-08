import 'package:flutter/material.dart';

import '../count/count_cells.dart';
import '../data/count_line.dart';
import '../data/history_store.dart';
import '../logic/formatting.dart';
import '../theme/app_theme.dart';
import '../widgets/category_title.dart';
import '../widgets/status_chip.dart';

// the barista's history: past days on the left, the picked day on the right
// it only shows what was counted, tallied and written, never expected numbers
// corrections come in feature 8b
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.store});

  // null while the app is still loading
  final HistoryStore? store;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  // width of the day list, the details get the rest
  static const double _listWidth = 230;

  // how wide each column of the count table is compared to the others (flex)
  static const int _nameFlex = 6;
  static const int _unitFlex = 4;
  static const int _numberFlex = 2;

  // null while loading
  List<BusinessDay>? _days;
  int? _selectedId;
  // the picked day, null while it loads
  HistoryDetail? _detail;

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  // reads the days and opens the newest one
  Future<void> _loadDays() async {
    final store = widget.store;
    if (store == null) return;

    final days = await store.days();
    // mounted = this screen is still open
    if (!mounted) return;
    setState(() => _days = days);
    if (days.isNotEmpty) await _select(days.first.id);
  }

  Future<void> _select(int dayId) async {
    setState(() {
      _selectedId = dayId;
      _detail = null;
    });
    final detail = await widget.store!.detail(dayId);
    // a fast tap on another day could have come first, then this one is old
    if (!mounted || _selectedId != dayId) return;
    setState(() => _detail = detail);
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    if (days == null) {
      return const Card(child: Center(child: CircularProgressIndicator()));
    }
    if (days.isEmpty) return _noDays(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _listWidth, child: _dayList(context, days)),
        const SizedBox(width: 12),
        Expanded(child: Card(child: _details(context))),
      ],
    );
  }

  // shown before the first submit
  Widget _noDays(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 10),
            Text('No submitted days yet', style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Days show here after Submit.', style: text.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _dayList(BuildContext context, List<BusinessDay> days) {
    return Card(
      // clip so the picked day's background follows the round corners
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Text(
              'Past days',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: [for (final day in days) _dayTile(context, day)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayTile(BuildContext context, BusinessDay day) {
    final covers = day.coversFrom;

    // Material + InkWell = tap ripple, the picked day gets a cream background
    return Material(
      color: day.id == _selectedId ? AppColors.cream : Colors.transparent,
      child: InkWell(
        key: Key('history_day_${day.id}'),
        onTap: () => _select(day.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatLongDate(day.businessDate),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _statusChip(day),
                ],
              ),
              if (covers != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Covers ${formatCovers(covers, day.businessDate)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(BusinessDay day) {
    return day.status == 'closed'
        ? const StatusChip(label: 'Closed', tone: ChipTone.warn)
        : const StatusChip(label: 'Submitted', tone: ChipTone.ok);
  }

  // the picked day: a header, then its count, tally and day note
  Widget _details(BuildContext context) {
    final detail = _detail;
    if (detail == null) return const Center(child: CircularProgressIndicator());

    final day = detail.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailHeader(context, day),
        const Divider(),
        Expanded(
          child: day.status == 'closed'
              ? _closedMessage(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    ..._countSection(context, detail.rows),
                    ..._tallySection(context, detail),
                    if (day.dayNote != null) ...[
                      _sectionTitle(context, 'Day note'),
                      Text(day.dayNote!),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _detailHeader(BuildContext context, BusinessDay day) {
    final text = Theme.of(context).textTheme;
    final covers = day.coversFrom;
    final submittedAt = day.submittedAt;

    // the small line under the date, like "Covers Oct 29–30 · Submitted 6:12pm"
    final parts = [
      if (covers != null) 'Covers ${formatCovers(covers, day.businessDate)}',
      // the db keeps utc, the tablet shows its own time
      if (submittedAt != null)
        'Submitted ${formatTime(DateTime.parse(submittedAt).toLocal())}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatLongDate(day.businessDate), style: text.titleMedium),
                if (parts.isNotEmpty)
                  Text(parts.join(' · '), style: text.bodySmall),
              ],
            ),
          ),
          _statusChip(day),
        ],
      ),
    );
  }

  Widget _closedMessage(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.storefront_outlined,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 10),
          Text(
            'The cafe was closed this day.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  // the count table grouped by category, same cells as the count tab
  List<Widget> _countSection(BuildContext context, List<CountRow> rows) {
    final widgets = <Widget>[_sectionTitle(context, 'Count'), _tableHeader()];
    String? category;
    for (final row in rows) {
      // the rows come ordered by category, so a new name means a new group
      if (row.item.category.toLowerCase() != category?.toLowerCase()) {
        category = row.item.category;
        widgets.add(CategoryTitle(category));
      }
      widgets.add(_countRow(row));
    }
    return widgets;
  }

  // the column names, a cream strip like the count tab
  Widget _tableHeader() {
    const style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    );

    return Container(
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
          for (final label in ['Start', 'In', 'Out', 'End'])
            Expanded(
              flex: _numberFlex,
              child: Text(label, textAlign: TextAlign.right, style: style),
            ),
        ],
      ),
    );
  }

  // one logbook row, the item note sits under the name
  Widget _countRow(CountRow row) {
    final line = row.line;
    final item = row.item;
    final note = line.note;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: _nameFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (note != null)
                  Text(
                    'Note: $note',
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: _unitFlex,
            child: Text(unitText(item), style: const TextStyle(fontSize: 12)),
          ),
          _number(shownAmount(item, line.startQty)),
          _number(shownAmount(item, line.inQty)),
          _number(outText(item, line)),
          _number(shownAmount(item, line.endQty), bold: true),
        ],
      ),
    );
  }

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

  // the menu items made that day, like "Latte × 3"
  List<Widget> _tallySection(BuildContext context, HistoryDetail detail) {
    return [
      _sectionTitle(context, 'Tally'),
      if (detail.tally.isEmpty)
        Text('Nothing tallied', style: Theme.of(context).textTheme.bodySmall),
      for (final row in detail.tally)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(child: Text(row.item.name)),
              Text(
                '× ${row.qty}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
    ];
  }
}
