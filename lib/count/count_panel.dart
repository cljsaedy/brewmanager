import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/count_line.dart';
import '../data/count_store.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import '../theme/app_theme.dart';
import 'count_badges.dart';

// the opened level buttons in the order they show on screen, the correction form uses them too
const Map<String, double> levelButtons = {
  'None': levelNone,
  'Almost empty': levelAlmostEmpty,
  '25%': level25,
  '50%': level50,
  '75%': level75,
  'Full': levelFull,
};

// the right side panel for the selected logbook row, everything here autosaves (rule 4)
class CountPanel extends StatefulWidget {
  const CountPanel({
    super.key,
    required this.store,
    required this.row,
    required this.onChanged,
    required this.onClose,
  });

  final CountStore store;
  final CountRow row;
  // called after every save so the table reads the new numbers
  final VoidCallback onChanged;
  final VoidCallback onClose;

  @override
  State<CountPanel> createState() => _CountPanelState();
}

class _CountPanelState extends State<CountPanel> {
  // below this height the keyboard is open, then the badges hide so the panel still fits
  static const double _minHeightForBadges = 240;

  // how long the short message stays after a finish or undo
  static const Duration _messageTime = Duration(seconds: 3);

  // kept here and not read back from the row, a fast second tap has to build on the first one
  // even if the db has not finished saving it yet
  late int _sealed;
  late double _level;
  late double? _exactQty;
  // containers finished today, kept here too so undo turns on right after a tap
  late int _finished;

  // true while an undo is saving, its new values only come back from the db
  // so count taps wait until then, otherwise they would build on the wrong numbers
  bool _undoing = false;

  late final TextEditingController _exactBox;
  late final TextEditingController _numberBox;
  late final TextEditingController _noteBox;
  late final TextEditingController _lowBox;
  late final TextEditingController _inBox;

  // restocks being removed right now, they leave the list at once so a double tap cant hit them again
  final Set<int> _removing = {};

  bool get _isContainer => widget.row.item.countType == CountType.container;

  // no sealed and nothing open = nothing to finish
  bool get _canFinish =>
      canFinishContainer(sealed: _sealed, level: _level, exactQty: _exactQty);

  // the whole number typed in the restock box, null if it is empty or 0
  int? get _inAmount {
    final amount = int.tryParse(_inBox.text);
    return amount == null || amount <= 0 ? null : amount;
  }

  @override
  void initState() {
    super.initState();
    final line = widget.row.line;
    _sealed = line.sealed ?? 0;
    _level = line.level ?? levelNone;
    _exactQty = line.exactQty;
    _finished = line.outCount;

    final exact = line.exactQty;
    _exactBox = TextEditingController(
      text: exact == null ? '' : plainNumber(exact),
    );
    _numberBox = TextEditingController(text: plainNumber(line.endQty));
    _noteBox = TextEditingController(text: line.note ?? '');
    _lowBox = TextEditingController(
      text: plainNumber(widget.row.item.lowValue),
    );
    _inBox = TextEditingController();
  }

  // text boxes hold memory so they have to be closed when the panel goes away
  @override
  void dispose() {
    _exactBox.dispose();
    _numberBox.dispose();
    _noteBox.dispose();
    _lowBox.dispose();
    _inBox.dispose();
    super.dispose();
  }

  // saves sealed, level and exact together, then lets the table reload
  Future<void> _saveCount() async {
    await widget.store.saveContainerCount(
      widget.row,
      sealed: _sealed,
      level: _level,
      exactQty: _exactQty,
    );
    widget.onChanged();
  }

  void _setSealed(int sealed) {
    if (_undoing) return;
    setState(() => _sealed = sealed);
    _saveCount();
  }

  // a level button replaces a typed exact amount, only one of them can be the opened part
  void _setLevel(double level) {
    if (_undoing) return;
    setState(() {
      _level = level;
      _exactQty = null;
    });
    _exactBox.clear();
    _saveCount();
  }

  // a typed amount replaces the level, an empty box goes back to the level
  // something that isnt a number yet, like a lone dot, is not saved
  void _onExactTyped(String text) {
    if (_undoing) return;
    final isEmpty = text.trim().isEmpty;
    final value = readNumber(text);
    if (!isEmpty && value == null) return;

    setState(() => _exactQty = isEmpty ? null : value);
    _saveCount();
  }

  // an empty box is not saved, the last number stays until a new one is typed
  Future<void> _onNumberTyped(String text) async {
    final value = readNumber(text);
    if (value == null) return;

    await widget.store.saveNumberCount(widget.row.line.id, value);
    widget.onChanged();
  }

  Future<void> _onNoteTyped(String text) async {
    await widget.store.saveNote(widget.row.line.id, text);
    widget.onChanged();
  }

  // an empty box is not saved, same as the number box
  Future<void> _onLowTyped(String text) async {
    final value = readNumber(text);
    if (value == null) return;

    await widget.store.saveLowValue(widget.row.item.id!, value);
    widget.onChanged();
  }

  // adds the typed restock, the box takes containers but the db keeps base units (rule 1)
  // sealed changes here right away too, so a fast tap on + right after builds on the new number
  Future<void> _addRestock() async {
    final amount = _inAmount;
    if (amount == null || _undoing) return;

    // cleared before saving so a double tap finds an empty box and adds nothing
    _inBox.clear();
    final item = widget.row.item;
    final qty = _isContainer
        ? roundAmount(amount * item.containerSize!)
        : amount.toDouble();
    setState(() {
      if (_isContainer) _sealed += amount;
    });

    final saved = await widget.store.addRestock(widget.row, qty);
    _afterRestock(saved);
  }

  // takes the restock back out, same idea as adding one
  Future<void> _removeRestock(Restock restock) async {
    if (_undoing || !_removing.add(restock.id)) return;

    setState(() {
      if (_isContainer) {
        final containers = containersIn(
          restock.qty,
          widget.row.item.containerSize!,
        );
        _sealed = sealedAfterRemove(_sealed, containers);
      }
    });

    final saved = await widget.store.removeRestock(widget.row, restock);
    _afterRestock(saved);
  }

  // the number box shows End so it has to follow the restock
  // mounted = the panel could have been closed while saving, then the box is gone
  void _afterRestock(CountLine saved) {
    if (mounted && !_isContainer) {
      _numberBox.text = plainNumber(saved.endQty);
    }
    widget.onChanged();
  }

  // one tap on container finished (rule 3), the store does the same math and saves it
  // the numbers change here right away too, so a fast next tap builds on them
  Future<void> _finishContainer() async {
    if (_undoing || !_canFinish) return;

    final sealedBefore = _sealed;
    setState(() {
      _finished++;
      _sealed = sealedAfterFinish(sealedBefore);
      _level = levelAfterFinish(sealedBefore);
      _exactQty = null;
    });
    _exactBox.clear();
    _showChange(
      '${capitalized(widget.row.item.containerName)} finished',
      sealedBefore,
    );

    await widget.store.finishContainer(widget.row);
    widget.onChanged();
  }

  // undoes the last finished container, the store works out what that tap changed
  Future<void> _undoFinish() async {
    if (_undoing || _finished == 0) return;

    final sealedBefore = _sealed;
    _undoing = true;
    setState(() => _finished--);
    final saved = await widget.store.undoFinish(widget.row);
    _undoing = false;

    // mounted = the panel could have been closed while saving
    if (mounted) {
      setState(() {
        _sealed = saved.sealed!;
        _level = saved.level ?? levelNone;
        _exactQty = saved.exactQty;
      });
      final exact = saved.exactQty;
      _exactBox.text = exact == null ? '' : plainNumber(exact);
      _showChange('Undone', sealedBefore);
    }
    widget.onChanged();
  }

  // what opened is now in words, like "50%" or "350 ml"
  String _openedText() {
    final exact = _exactQty;
    if (exact != null) {
      return formatWithUnit(exact, widget.row.item.baseUnit.name);
    }
    for (final button in levelButtons.entries) {
      if (button.value == _level) return button.key;
    }
    return '';
  }

  // short message on what a finish or undo changed, so nobody also taps sealed - by mistake
  // sealed is left out of the message when the tap didnt change it
  // clearSnackBars = a fast next tap replaces the message instead of waiting in line
  void _showChange(String what, int sealedBefore) {
    final sealed = sealedBefore == _sealed
        ? ''
        : 'Sealed $sealedBefore → $_sealed, ';

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('$what. ${sealed}Opened: ${_openedText()}.'),
          duration: _messageTime,
        ),
      );
  }

  // one restock in the list, like "+2 bottles · 2:15pm"
  String _restockText(Restock restock) {
    final item = widget.row.item;
    final amount = _isContainer
        ? formatContainers(
            restock.qty / item.containerSize!,
            item.containerName,
          )
        : formatWithUnit(restock.qty, item.baseUnit.name);
    return '+$amount · ${formatTime(restock.time)}';
  }

  // the End under the title, always with the base amount (rule 1)
  // a count with a level in it is only an estimate so it says about (rule 2)
  String _endText() {
    final line = widget.row.line;
    final item = widget.row.item;
    final baseAmount = formatWithUnit(line.endQty, item.baseUnit.name);
    if (!_isContainer) return 'End: $baseAmount';

    final containers = formatContainers(
      line.endQty / item.containerSize!,
      item.containerName,
    );
    final about = line.endIsExact ? '' : 'about ';
    return 'End: $about$containers ($baseAmount)';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // LayoutBuilder = tells how much height the panel really gets right now
    return LayoutBuilder(
      builder: (context, size) {
        final isTall = size.maxHeight >= _minHeightForBadges;

        return Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // title + close
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.row.item.name,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(_endText(), style: text.bodySmall),
                          // the table hides its badges while this panel is open, so they show here
                          // the keyboard leaves too little height, they come back when it closes
                          if (widget.row.hasBadges && isTall) ...[
                            const SizedBox(height: 6),
                            CountBadges(widget.row),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const Divider(),
              // scrolls since the keyboard takes half of the screen
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isContainer) ...[
                        _sealedPart(context),
                        _partLine(),
                        _openedPart(context),
                      ] else
                        _numberField(),
                      _partLine(),
                      _inPart(context),
                      _partLine(),
                      if (_isContainer) ...[_outPart(context), _partLine()],
                      _noteField(),
                      _partLine(),
                      _lowField(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // the thin line between 2 parts of the panel, same look as the table rows
  Widget _partLine() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(),
    );
  }

  // sealed containers with - and +, it cant go below 0
  Widget _sealedPart(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(child: Text('Sealed', style: text.titleSmall)),
        IconButton.outlined(
          key: const Key('sealed_minus'),
          onPressed: _sealed == 0 ? null : () => _setSealed(_sealed - 1),
          icon: const Icon(Icons.remove),
          tooltip: 'One less',
        ),
        SizedBox(
          width: 52,
          child: Text(
            '$_sealed',
            key: const Key('sealed_value'),
            textAlign: TextAlign.center,
            style: text.titleMedium,
          ),
        ),
        IconButton.outlined(
          key: const Key('sealed_plus'),
          onPressed: () => _setSealed(_sealed + 1),
          icon: const Icon(Icons.add),
          tooltip: 'One more',
        ),
      ],
    );
  }

  // the level buttons and the exact box, exact replaces the level (rule 2)
  // tapping the button that is already on still saves, so "still 50%" marks the line touched
  Widget _openedPart(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Opened', style: text.titleSmall),
        const SizedBox(height: 8),
        // Wrap = goes to the next line when a row of buttons is full
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final button in levelButtons.entries)
              ChoiceChip(
                label: Text(button.key),
                selected: _exactQty == null && _level == button.value,
                showCheckmark: false,
                selectedColor: AppColors.cream,
                onSelected: (_) => _setLevel(button.value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('exact_field'),
          controller: _exactBox,
          onChanged: _onExactTyped,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Type exact amount',
            suffixText: widget.row.item.baseUnit.name,
          ),
        ),
      ],
    );
  }

  // number items only have this one box, whole numbers only (rule 2)
  Widget _numberField() {
    return TextField(
      key: const Key('number_field'),
      controller: _numberBox,
      onChanged: _onNumberTyped,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Number',
        suffixText: widget.row.item.baseUnit.name,
      ),
    );
  }

  // restock box and today's restocks, it can be added to several times a day (rule 3)
  // whole numbers only since restocks arrive sealed, so no half bottles here
  Widget _inPart(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.row.item;
    final restocks = widget.row.restocks.where(
      (restock) => !_removing.contains(restock.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('In', style: text.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('in_field'),
                controller: _inBox,
                // only redraws so the Add button turns on and off
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Add restock',
                  suffixText: _isContainer
                      ? pluralOf(item.containerName)
                      : item.baseUnit.name,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('in_add'),
              onPressed: _inAmount == null ? null : _addRestock,
              child: const Text('Add'),
            ),
          ],
        ),
        for (final restock in restocks)
          Row(
            children: [
              Expanded(child: Text(_restockText(restock))),
              IconButton(
                key: ValueKey('in_remove_${restock.id}'),
                onPressed: () => _removeRestock(restock),
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove restock',
              ),
            ],
          ),
      ],
    );
  }

  // container items only, number items work out their Out from the count (rule 3)
  // the button says the container's name, like "Bottle finished"
  // containerName already says "container" when no name was typed
  Widget _outPart(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Out', style: text.titleSmall),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('out_finish'),
          onPressed: _canFinish ? _finishContainer : null,
          child: Text('${capitalized(widget.row.item.containerName)} finished'),
        ),
        if (!_canFinish) ...[
          const SizedBox(height: 4),
          Text('Nothing open to finish.', style: text.bodySmall),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text('Finished today')),
            IconButton.outlined(
              key: const Key('out_undo'),
              onPressed: _finished == 0 ? null : _undoFinish,
              icon: const Icon(Icons.remove),
              tooltip: 'Undo last finished',
            ),
            SizedBox(
              width: 52,
              child: Text(
                '$_finished',
                key: const Key('out_value'),
                textAlign: TextAlign.center,
                style: text.titleMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _noteField() {
    return TextField(
      key: const Key('note_field'),
      controller: _noteBox,
      onChanged: _onNoteTyped,
      minLines: 1,
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(labelText: 'Note (optional)'),
    );
  }

  // the unit next to the box comes from the mode the owner picked, like "bottles" or "g"
  Widget _lowField() {
    final item = widget.row.item;

    return TextField(
      key: const Key('low_field'),
      controller: _lowBox,
      onChanged: _onLowTyped,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      decoration: InputDecoration(
        labelText: 'Low-stock level',
        suffixText: item.lowMode == LowMode.containers
            ? pluralOf(item.containerName)
            : item.baseUnit.name,
      ),
    );
  }
}
