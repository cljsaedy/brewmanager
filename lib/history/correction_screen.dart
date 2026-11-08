import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../count/count_cells.dart';
import '../count/count_panel.dart';
import '../data/correction_store.dart';
import '../data/count_line.dart';
import '../data/count_store.dart';
import '../data/history_store.dart';
import '../data/stock_item.dart';
import '../data/tally_store.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import '../submit/submit_widgets.dart';
import '../theme/app_theme.dart';

// what can be picked on the left
enum _Kind { count, tally, dayNote }

// the picked thing: a stock item, a menu item, or the day note (id 0)
class _Pick {
  const _Pick(this.kind, this.id);

  final _Kind kind;
  final int id;

  @override
  bool operator ==(Object other) =>
      other is _Pick && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

// fixes on the latest submitted day (rule 4): pick something on the left, change it on the right
// every save needs a reason, gets logged, and queues a short email to the owner
// no expected numbers here, this is the barista side
class CorrectionScreen extends StatefulWidget {
  const CorrectionScreen({super.key, required this.store, required this.dayId});

  final CountStore store;
  final int dayId;

  @override
  State<CorrectionScreen> createState() => _CorrectionScreenState();
}

class _CorrectionScreenState extends State<CorrectionScreen> {
  // width of the list on the left, the form gets the rest
  static const double _listWidth = 300;

  // both null while loading
  HistoryDetail? _detail;
  List<TallyRow>? _tally;
  _Pick? _pick;

  // the form, filled from the saved values when something is picked
  int _sealed = 0;
  double _level = levelNone;
  // containers restocked, container items only, number items use _inBox
  int _inContainers = 0;
  int _out = 0;
  int _qty = 0;
  final TextEditingController _exactBox = TextEditingController();
  final TextEditingController _numberBox = TextEditingController();
  final TextEditingController _inBox = TextEditingController();
  final TextEditingController _noteBox = TextEditingController();
  final TextEditingController _reasonBox = TextEditingController();

  // true while saving, the save button is off so a double tap saves once
  bool _saving = false;

  CorrectionStore get _fixes => widget.store.corrections;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _exactBox.dispose();
    _numberBox.dispose();
    _inBox.dispose();
    _noteBox.dispose();
    _reasonBox.dispose();
    super.dispose();
  }

  // reads the day again, after a save too so the left side shows the new values
  Future<void> _load() async {
    final detail = await widget.store.history.detail(widget.dayId);
    final tally = await widget.store.tally.load(widget.dayId);
    // mounted = this screen is still open
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _tally = tally;
    });
  }

  CountRow? _rowOf(int stockItemId) {
    for (final row in _detail!.rows) {
      if (row.item.id == stockItemId) return row;
    }
    return null;
  }

  int _qtyOf(int menuItemId) {
    for (final row in _tally!) {
      if (row.item.id == menuItemId) return row.qty;
    }
    return 0;
  }

  // picks something and fills the form with what is saved now
  void _select(_Pick pick) {
    FocusScope.of(context).unfocus();
    setState(() {
      _pick = pick;
      _reasonBox.clear();
      switch (pick.kind) {
        case _Kind.count:
          final line = _rowOf(pick.id)!.line;
          final item = _rowOf(pick.id)!.item;
          _sealed = line.sealed ?? 0;
          _level = line.level ?? levelNone;
          _exactBox.text = line.exactQty == null
              ? ''
              : plainNumber(line.exactQty!);
          _numberBox.text = plainNumber(line.endQty);
          _inBox.text = plainNumber(line.inQty);
          _inContainers = item.countType == CountType.container
              ? containersIn(line.inQty, item.containerSize!)
              : 0;
          _out = line.outCount;
          _noteBox.text = line.note ?? '';
        case _Kind.tally:
          _qty = _qtyOf(pick.id);
        case _Kind.dayNote:
          _noteBox.text = _detail!.day.dayNote ?? '';
      }
    });
  }

  // true when the form can be saved: a reason, and the number boxes hold numbers
  bool get _canSave {
    final pick = _pick;
    if (pick == null || _saving || _reasonBox.text.trim().isEmpty) return false;
    if (pick.kind != _Kind.count) return true;

    final item = _rowOf(pick.id)!.item;
    if (item.countType == CountType.container) {
      return _exactBox.text.trim().isEmpty ||
          readNumber(_exactBox.text) != null;
    }
    return readNumber(_numberBox.text) != null &&
        readNumber(_inBox.text) != null;
  }

  Future<void> _save() async {
    final pick = _pick!;
    final reason = _reasonBox.text;
    setState(() => _saving = true);

    try {
      final changed = switch (pick.kind) {
        _Kind.count => await _fixes.correctCount(
          widget.dayId,
          pick.id,
          _countFix(_rowOf(pick.id)!),
          reason,
        ),
        _Kind.tally => await _fixes.correctTally(
          widget.dayId,
          pick.id,
          _qty,
          reason,
        ),
        _Kind.dayNote => await _fixes.correctDayNote(
          widget.dayId,
          _noteBox.text,
          reason,
        ),
      };
      await _load();
      if (!mounted) return;
      _select(pick);
      _message(
        changed
            ? 'Correction saved. The owner will get an email about it.'
            : 'Nothing changed, so nothing was saved.',
      );
    } on StateError {
      // the next day got submitted while this screen was open, this day is final now
      _message('This day cant be corrected anymore.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // the fix from the form, in base units like everything in the db
  CountFix _countFix(CountRow row) {
    final item = row.item;
    final line = row.line;
    final note = _noteBox.text;

    if (item.countType == CountType.container) {
      final exact = readNumber(_exactBox.text);
      // the same number of containers keeps the saved amount, so nothing changes by rounding
      final sameIn =
          _inContainers == containersIn(line.inQty, item.containerSize!);
      return CountFix(
        sealed: _sealed,
        level: _level,
        exactQty: exact,
        inQty: sameIn ? line.inQty : _inContainers * item.containerSize!,
        outCount: _out,
        note: note,
      );
    }
    return CountFix(
      number: readNumber(_numberBox.text)!,
      inQty: readNumber(_inBox.text)!,
      outCount: line.outCount,
      note: note,
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final tally = _tally;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: detail == null || tally == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SubmitHeader(
                      title:
                          'Correct ${formatLongDate(detail.day.businessDate)}',
                      subtitle:
                          'Each fix needs a reason. The owner gets an email.',
                      actions: [
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _listWidth,
                            child: _pickList(detail, tally),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _form()),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // the left side: count items, tally items and the day note
  Widget _pickList(HistoryDetail detail, List<TallyRow> tally) {
    return SectionCard(
      title: 'Pick what to fix',
      children: [
        const ListTitle('Count'),
        for (final row in detail.rows)
          _pickTile(
            _Pick(_Kind.count, row.item.id!),
            row.item.name,
            'End ${shownAmount(row.item, row.line.endQty)} · '
            'In ${shownAmount(row.item, row.line.inQty)} · '
            'Out ${outText(row.item, row.line)}',
          ),
        const ListTitle('Tally'),
        for (final row in tally)
          _pickTile(
            _Pick(_Kind.tally, row.item.id!),
            row.item.name,
            '× ${row.qty}',
          ),
        const ListTitle('Day'),
        _pickTile(
          const _Pick(_Kind.dayNote, 0),
          'Day note',
          detail.day.dayNote ?? 'No day note',
        ),
      ],
    );
  }

  Widget _pickTile(_Pick pick, String title, String detail) {
    final isPicked = pick == _pick;

    // Material + InkWell = tap ripple, the picked one gets a cream background
    return Material(
      color: isPicked ? AppColors.cream : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      child: InkWell(
        key: Key('fix_${pick.kind.name}_${pick.id}'),
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        onTap: () => _select(pick),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // the right side: the fields of the picked thing, then the reason and save
  Widget _form() {
    final pick = _pick;
    if (pick == null) {
      return const SubmitCard(
        child: Center(
          child: EmptyLine(
            'Pick an item, a tally line or the day note on the left.',
            icon: Icons.touch_app_outlined,
          ),
        ),
      );
    }

    final text = Theme.of(context).textTheme;
    final List<Widget> fields;
    final String title;
    switch (pick.kind) {
      case _Kind.count:
        final row = _rowOf(pick.id)!;
        title = row.item.name;
        fields = _countFields(row);
      case _Kind.tally:
        title = _tally!.firstWhere((row) => row.item.id == pick.id).item.name;
        fields = [_stepper('How many', _qty, (value) => _qty = value, 'qty')];
      case _Kind.dayNote:
        title = 'Day note';
        fields = [
          _textBox(_noteBox, 'Day note', 'day_note_field', maxLines: 3),
        ];
    }

    return SubmitCard(
      padding: 0,
      child: ListView(
        key: const Key('correction_form'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: 12),
          ...fields,
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          _textBox(_reasonBox, 'Reason (needed)', 'reason_field'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('save_correction'),
              onPressed: _canSave ? _save : null,
              child: const Text('Save correction'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _countFields(CountRow row) {
    final item = row.item;
    if (item.countType == CountType.number) {
      return [
        _amountBox(_numberBox, 'End', 'end_field', item.baseUnit.name),
        const SizedBox(height: 12),
        _amountBox(_inBox, 'In', 'in_field', item.baseUnit.name),
        const SizedBox(height: 12),
        _textBox(_noteBox, 'Note', 'note_field'),
      ];
    }

    return [
      _stepper('Sealed', _sealed, (value) => _sealed = value, 'sealed'),
      const SizedBox(height: 12),
      _openedPart(item),
      const SizedBox(height: 12),
      _stepper(
        'In (${pluralOf(item.containerName)})',
        _inContainers,
        (value) => _inContainers = value,
        'in',
      ),
      const SizedBox(height: 4),
      _stepper(
        'Out (${pluralOf(item.containerName)} finished)',
        _out,
        (value) => _out = value,
        'out',
      ),
      const SizedBox(height: 12),
      _textBox(_noteBox, 'Note', 'note_field'),
    ];
  }

  // the level buttons and the exact box, same as the count panel, exact replaces the level (rule 2)
  Widget _openedPart(StockItem item) {
    final hasExact = _exactBox.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Opened', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final button in levelButtons.entries)
              ChoiceChip(
                label: Text(button.key),
                selected: !hasExact && _level == button.value,
                showCheckmark: false,
                selectedColor: AppColors.cream,
                onSelected: (_) => setState(() {
                  _level = button.value;
                  _exactBox.clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _amountBox(
          _exactBox,
          'Type exact amount',
          'exact_field',
          item.baseUnit.name,
          decimals: true,
        ),
      ],
    );
  }

  // a whole number with - and +, it cant go below 0
  Widget _stepper(
    String label,
    int value,
    void Function(int) onChanged,
    String key,
  ) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleSmall),
        ),
        IconButton.outlined(
          key: Key('${key}_minus'),
          onPressed: value == 0
              ? null
              : () => setState(() => onChanged(value - 1)),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$value',
            key: Key('${key}_value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton.outlined(
          key: Key('${key}_plus'),
          onPressed: () => setState(() => onChanged(value + 1)),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  // a number box with its unit, setState on every change so the save button updates
  Widget _amountBox(
    TextEditingController controller,
    String label,
    String key,
    String unit, {
    bool decimals = false,
  }) {
    return TextField(
      key: Key(key),
      controller: controller,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.numberWithOptions(decimal: decimals),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimals ? RegExp(r'[\d.,]') : RegExp(r'[\d,]'),
        ),
      ],
      decoration: InputDecoration(labelText: label, suffixText: unit),
    );
  }

  Widget _textBox(
    TextEditingController controller,
    String label,
    String key, {
    int maxLines = 1,
  }) {
    return TextField(
      key: Key(key),
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label),
    );
  }
}
