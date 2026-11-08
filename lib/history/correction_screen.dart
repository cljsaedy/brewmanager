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

// everything the form holds at one moment
// kept with each waiting change so tapping the item again shows what was added,
// and kept from when an item was picked so the screen knows if the form was edited since
class _Form {
  const _Form({
    this.sealed = 0,
    this.level = levelNone,
    this.inContainers = 0,
    this.out = 0,
    this.qty = 0,
    this.exactText = '',
    this.numberText = '',
    this.inText = '',
    this.noteText = '',
    this.reason = '',
  });

  final int sealed;
  final double level;
  // containers restocked, container items only, number items use inText
  final int inContainers;
  final int out;
  // the tally number
  final int qty;
  final String exactText;
  final String numberText;
  final String inText;
  final String noteText;
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is _Form &&
      other.sealed == sealed &&
      other.level == level &&
      other.inContainers == inContainers &&
      other.out == out &&
      other.qty == qty &&
      other.exactText == exactText &&
      other.numberText == numberText &&
      other.inText == inText &&
      other.noteText == noteText &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(
    sealed,
    level,
    inContainers,
    out,
    qty,
    exactText,
    numberText,
    inText,
    noteText,
    reason,
  );
}

// fixes on the latest submitted day (rule 4): pick something on the left, change it on the right
// "add change" only puts the change in a waiting list, nothing is saved yet
// "save corrections" saves every waiting change at once (1 transaction) and the owner gets 1 email
// "cancel" or back throws the waiting changes away, after asking
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

  // the changes added but not saved yet, a map keeps the order they were first added
  final Map<_Pick, _Form> _waiting = {};
  // the form as it was when the item was picked (or its change was added)
  _Form _loaded = const _Form();

  // the form fields
  int _sealed = 0;
  double _level = levelNone;
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

  String _nameOf(_Pick pick) {
    return switch (pick.kind) {
      _Kind.count => _rowOf(pick.id)!.item.name,
      _Kind.tally =>
        _tally!.firstWhere((row) => row.item.id == pick.id).item.name,
      _Kind.dayNote => 'Day note',
    };
  }

  // the form filled with what is saved in the db now
  _Form _savedForm(_Pick pick) {
    switch (pick.kind) {
      case _Kind.count:
        final row = _rowOf(pick.id)!;
        final line = row.line;
        final item = row.item;
        return _Form(
          sealed: line.sealed ?? 0,
          level: line.level ?? levelNone,
          exactText: line.exactQty == null ? '' : plainNumber(line.exactQty!),
          numberText: plainNumber(line.endQty),
          inText: plainNumber(line.inQty),
          inContainers: item.countType == CountType.container
              ? containersIn(line.inQty, item.containerSize!)
              : 0,
          out: line.outCount,
          noteText: line.note ?? '',
        );
      case _Kind.tally:
        return _Form(qty: _qtyOf(pick.id));
      case _Kind.dayNote:
        return _Form(noteText: _detail!.day.dayNote ?? '');
    }
  }

  // what the form fields hold right now
  _Form get _current => _Form(
    sealed: _sealed,
    level: _level,
    inContainers: _inContainers,
    out: _out,
    qty: _qty,
    exactText: _exactBox.text,
    numberText: _numberBox.text,
    inText: _inBox.text,
    noteText: _noteBox.text,
    reason: _reasonBox.text,
  );

  void _fill(_Form form) {
    _sealed = form.sealed;
    _level = form.level;
    _inContainers = form.inContainers;
    _out = form.out;
    _qty = form.qty;
    _exactBox.text = form.exactText;
    _numberBox.text = form.numberText;
    _inBox.text = form.inText;
    _noteBox.text = form.noteText;
    _reasonBox.text = form.reason;
  }

  // true when the form was edited since the item was picked and that edit is not added yet
  bool get _hasUnaddedEdit => _pick != null && _current != _loaded;

  // picks something, shows its waiting change if it has one, else what is saved
  Future<void> _select(_Pick pick) async {
    if (pick == _pick) return;
    if (_hasUnaddedEdit && !await _confirmDropEdit()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _pick = pick;
      _loaded = _waiting[pick] ?? _savedForm(pick);
      _fill(_loaded);
    });
  }

  // the number boxes hold numbers
  bool _formIsValid(_Pick pick) {
    if (pick.kind != _Kind.count) return true;
    final item = _rowOf(pick.id)!.item;
    if (item.countType == CountType.container) {
      return _exactBox.text.trim().isEmpty ||
          readNumber(_exactBox.text) != null;
    }
    return readNumber(_numberBox.text) != null &&
        readNumber(_inBox.text) != null;
  }

  // true when the form is different from what is saved in the db
  bool _differsFromSaved(_Pick pick, _Form form) {
    switch (pick.kind) {
      case _Kind.count:
        final row = _rowOf(pick.id)!;
        return diffCount(row.item, row.line, _countFix(row, form)).any;
      case _Kind.tally:
        return form.qty != _qtyOf(pick.id);
      case _Kind.dayNote:
        return cleanNote(form.noteText) != _detail!.day.dayNote;
    }
  }

  // add change: something new in the form, it is different from the saved values, and it has a reason
  bool get _canAdd {
    final pick = _pick;
    if (pick == null || _saving || !_hasUnaddedEdit) return false;
    if (_reasonBox.text.trim().isEmpty || !_formIsValid(pick)) return false;
    return _differsFromSaved(pick, _current);
  }

  // puts the change in the waiting list, nothing is saved yet
  void _add() {
    FocusScope.of(context).unfocus();
    setState(() {
      _waiting[_pick!] = _current;
      _loaded = _current;
    });
  }

  // takes the change out of the waiting list and shows the saved values again
  void _undo() {
    final pick = _pick!;
    setState(() {
      _waiting.remove(pick);
      _loaded = _savedForm(pick);
      _fill(_loaded);
    });
  }

  // the fix from a form, in base units like everything in the db
  CountFix _countFix(CountRow row, _Form form) {
    final item = row.item;
    final line = row.line;

    if (item.countType == CountType.container) {
      // the same number of containers keeps the saved amount, so nothing changes by rounding
      final sameIn =
          form.inContainers == containersIn(line.inQty, item.containerSize!);
      return CountFix(
        sealed: form.sealed,
        level: form.level,
        exactQty: readNumber(form.exactText),
        inQty: sameIn ? line.inQty : form.inContainers * item.containerSize!,
        outCount: form.out,
        note: form.noteText,
      );
    }
    return CountFix(
      number: readNumber(form.numberText)!,
      inQty: readNumber(form.inText)!,
      outCount: line.outCount,
      note: form.noteText,
    );
  }

  Correction _correctionOf(_Pick pick, _Form form) {
    return switch (pick.kind) {
      _Kind.count => CountCorrection(
        pick.id,
        _countFix(_rowOf(pick.id)!, form),
        form.reason,
      ),
      _Kind.tally => TallyCorrection(pick.id, form.qty, form.reason),
      _Kind.dayNote => DayNoteCorrection(form.noteText, form.reason),
    };
  }

  // save corrections: every waiting change in 1 go, then back to history with how many were saved
  Future<void> _saveAll() async {
    if (_hasUnaddedEdit && !await _confirmDropEdit()) return;
    setState(() => _saving = true);

    try {
      final changes = [
        for (final entry in _waiting.entries)
          _correctionOf(entry.key, entry.value),
      ];
      final saved = await _fixes.saveAll(widget.dayId, changes);
      if (!mounted) return;
      // empty now so the back check lets the screen close
      _waiting.clear();
      _pick = null;
      Navigator.of(context).pop(saved);
    } on StateError {
      // the next day got submitted while this screen was open, this day is final now
      _message('This day cant be corrected anymore.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // cancel or back: asks first if something would be thrown away
  Future<void> _leave() async {
    if (_waiting.isNotEmpty || _hasUnaddedEdit) {
      if (!await _confirmDiscardAll()) return;
    }
    if (!mounted) return;
    _waiting.clear();
    _pick = null;
    Navigator.of(context).pop();
  }

  // the edit on the picked item was not added, asks before throwing it away
  Future<bool> _confirmDropEdit() {
    return _confirm(
      'Discard the change to ${_nameOf(_pick!)}?',
      'It was not added yet, so it would not be saved.',
    );
  }

  // the waiting changes, plus the edit on the picked item if it is not added yet
  Future<bool> _confirmDiscardAll() {
    final unadded = _hasUnaddedEdit && !_waiting.containsKey(_pick) ? 1 : 0;
    final count = _waiting.length + unadded;
    return _confirm(
      count == 1 ? 'Discard 1 change?' : 'Discard $count changes?',
      'Nothing will be saved and the owner gets no email.',
    );
  }

  // keep editing = false, discard = true, tapping outside the box = false too
  Future<bool> _confirm(String title, String body) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('discard_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  String get _waitingText {
    final count = _waiting.length;
    if (count == 0) return 'Pick something to fix. Each fix needs a reason.';
    final changes = count == 1 ? '1 change' : '$count changes';
    return '$changes waiting. Press Save corrections to save them.';
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final tally = _tally;
    final count = _waiting.length;

    // PopScope = catches the android back button, it goes through the same check as cancel
    return PopScope(
      canPop: _waiting.isEmpty && !_hasUnaddedEdit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
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
                        subtitle: _waitingText,
                        actions: [
                          OutlinedButton(
                            key: const Key('cancel_corrections'),
                            onPressed: _saving ? null : _leave,
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            key: const Key('save_corrections'),
                            onPressed: count == 0 || _saving ? null : _saveAll,
                            child: Text(
                              count == 0
                                  ? 'Save corrections'
                                  : 'Save corrections ($count)',
                            ),
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
            _countDetail(row),
          ),
        const ListTitle('Tally'),
        for (final row in tally)
          _pickTile(
            _Pick(_Kind.tally, row.item.id!),
            row.item.name,
            '× ${_waiting[_Pick(_Kind.tally, row.item.id!)]?.qty ?? row.qty}',
          ),
        const ListTitle('Day'),
        _pickTile(
          const _Pick(_Kind.dayNote, 0),
          'Day note',
          _dayNoteDetail(detail),
        ),
      ],
    );
  }

  // End, In and Out under the name, the new values when a change is waiting
  String _countDetail(CountRow row) {
    final item = row.item;
    final line = row.line;
    final form = _waiting[_Pick(_Kind.count, item.id!)];
    if (form == null) {
      return 'End ${shownAmount(item, line.endQty)} · '
          'In ${shownAmount(item, line.inQty)} · '
          'Out ${outText(item, line)}';
    }

    // same as outText but with the new values
    final fix = _countFix(row, form);
    final end = diffCount(item, line, fix).end;
    final String out;
    if (item.countType == CountType.container) {
      out = '${fix.outCount}';
    } else if (line.isOpening) {
      out = '—';
    } else {
      out = formatAmount(
        amountUsed(start: line.startQty, inQty: fix.inQty, end: end),
      );
    }
    return 'End ${shownAmount(item, end)} · '
        'In ${shownAmount(item, fix.inQty)} · '
        'Out $out';
  }

  String _dayNoteDetail(HistoryDetail detail) {
    final form = _waiting[const _Pick(_Kind.dayNote, 0)];
    final note = form == null ? detail.day.dayNote : cleanNote(form.noteText);
    return note ?? 'No day note';
  }

  Widget _pickTile(_Pick pick, String title, String detail) {
    final isPicked = pick == _pick;
    final isWaiting = _waiting.containsKey(pick);

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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isWaiting) const _ChangedBadge(),
            ],
          ),
        ),
      ),
    );
  }

  // the right side: the fields of the picked thing, then the reason and add change
  Widget _form() {
    final pick = _pick;
    if (pick == null) return const SubmitCard(child: _PickHint());

    final text = Theme.of(context).textTheme;
    final List<Widget> fields;
    switch (pick.kind) {
      case _Kind.count:
        fields = _countFields(_rowOf(pick.id)!);
      case _Kind.tally:
        fields = [_stepper('How many', _qty, (value) => _qty = value, 'qty')];
      case _Kind.dayNote:
        fields = [
          _textBox(_noteBox, 'Day note', 'day_note_field', maxLines: 3),
        ];
    }
    final isWaiting = _waiting.containsKey(pick);

    return SubmitCard(
      padding: 0,
      child: ListView(
        key: const Key('correction_form'),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text(_nameOf(pick), style: text.titleMedium)),
              if (isWaiting) const _ChangedBadge(),
            ],
          ),
          const SizedBox(height: 12),
          ...fields,
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          _textBox(_reasonBox, 'Reason (needed)', 'reason_field'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isWaiting) ...[
                TextButton.icon(
                  key: const Key('undo_change'),
                  onPressed: _saving ? null : _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo change'),
                ),
                const SizedBox(width: 10),
              ],
              FilledButton(
                key: const Key('add_change'),
                onPressed: _canAdd ? _add : null,
                child: Text(isWaiting ? 'Update change' : 'Add change'),
              ),
            ],
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

  // a number box with its unit, setState on every change so the add button updates
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

// small amber "Changed" tag on an item with a waiting change
class _ChangedBadge extends StatelessWidget {
  const _ChangedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Changed',
        style: TextStyle(
          color: AppColors.warnText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// what the right side shows before anything is picked, big and in the middle
class _PickHint extends StatelessWidget {
  const _PickHint();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.touch_app_outlined,
            size: 64,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            'Pick an item, a tally line or the day note on the left.',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
