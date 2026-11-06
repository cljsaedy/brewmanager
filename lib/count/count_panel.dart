import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/count_line.dart';
import '../data/count_store.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';
import '../theme/app_theme.dart';

// the opened level buttons in the order they show on screen
const Map<String, double> _levelButtons = {
  'None': levelNone,
  'Almost empty': levelAlmostEmpty,
  '25%': level25,
  '50%': level50,
  '75%': level75,
  'Full': levelFull,
};

// the right side panel for the selected logbook row, everything here autosaves (rule 4)
// the IN and OUT parts come in the next steps
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
  // kept here and not read back from the row, a fast second tap has to build on the first one
  // even if the db has not finished saving it yet
  late int _sealed;
  late double _level;
  late double? _exactQty;

  late final TextEditingController _exactBox;
  late final TextEditingController _numberBox;
  late final TextEditingController _noteBox;
  late final TextEditingController _lowBox;

  bool get _isContainer => widget.row.item.countType == CountType.container;

  @override
  void initState() {
    super.initState();
    final line = widget.row.line;
    _sealed = line.sealed ?? 0;
    _level = line.level ?? levelNone;
    _exactQty = line.exactQty;

    final exact = line.exactQty;
    _exactBox = TextEditingController(
      text: exact == null ? '' : plainNumber(exact),
    );
    _numberBox = TextEditingController(text: plainNumber(line.endQty));
    _noteBox = TextEditingController(text: line.note ?? '');
    _lowBox = TextEditingController(
      text: plainNumber(widget.row.item.lowValue),
    );
  }

  // text boxes hold memory so they have to be closed when the panel goes away
  @override
  void dispose() {
    _exactBox.dispose();
    _numberBox.dispose();
    _noteBox.dispose();
    _lowBox.dispose();
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
    setState(() => _sealed = sealed);
    _saveCount();
  }

  // a level button replaces a typed exact amount, only one of them can be the opened part
  void _setLevel(double level) {
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
                    const SizedBox(height: 18),
                    _openedPart(context),
                  ] else
                    _numberField(),
                  const SizedBox(height: 18),
                  _noteField(),
                  const SizedBox(height: 14),
                  _lowField(),
                ],
              ),
            ),
          ),
        ],
      ),
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
            for (final button in _levelButtons.entries)
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
