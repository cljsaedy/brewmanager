import 'package:flutter/material.dart';

import '../../data/stock_item.dart';
import '../../data/stock_item_store.dart';
import '../../logic/formatting.dart';
import '../../logic/units.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/message_box.dart';

// the right side panel for adding a new stock item or editing one
// item null = adding a new one
class StockItemForm extends StatefulWidget {
  const StockItemForm({
    super.key,
    required this.store,
    required this.item,
    required this.categories,
    required this.onDone,
    required this.onCancel,
  });

  final StockItemStore store;
  final StockItem? item;
  // categories already used, shown as tap-to-fill chips
  final List<String> categories;
  // called after saving or restoring, with the message for the snackbar
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  State<StockItemForm> createState() => _StockItemFormState();
}

class _StockItemFormState extends State<StockItemForm> {
  // text boxes
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _labelController = TextEditingController();
  final _sizeController = TextEditingController();
  final _lowController = TextEditingController();

  // the picked choices, new items start as a ml container with a containers low level
  CountType _countType = CountType.container;
  BaseUnit _baseUnit = BaseUnit.ml;
  LowMode _lowMode = LowMode.containers;
  // which unit the container size / exact low level is typed in, like L, changed to base on save
  late InputUnit _sizeUnit = _baseInputUnit(_baseUnit);
  late InputUnit _lowUnit = _baseInputUnit(_baseUnit);

  // true when the item is already used, then unit and count type cant change (rule 1)
  bool _locked = false;
  String? _error;
  // set when the typed name belongs to an archived item, shows the restore offer
  StockItem? _archivedMatch;
  // stops a double tap saving twice
  bool _saving = false;

  bool get _isNew => widget.item == null;
  bool get _isContainer => _countType == CountType.container;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item == null) return;

    // editing: fill the boxes with the saved values, amounts shown in the unit the owner typed them in
    _nameController.text = item.name;
    _categoryController.text = item.category;
    _labelController.text = item.containerLabel ?? '';
    _countType = item.countType;
    _baseUnit = item.baseUnit;
    _lowMode = item.lowMode;
    _sizeUnit = item.sizeInputUnit;
    _lowUnit = item.lowInputUnit;
    if (item.containerSize != null) {
      // like 2000 ml saved as L shows 2
      _sizeController.text = plainNumber(
        fromBaseUnit(item.containerSize!, _sizeUnit),
      );
    }
    _lowController.text = plainNumber(item.lowShown);
    _checkLocked(item.id!);
  }

  // asks the db if the item is used, then greys out unit and count type if it is
  Future<void> _checkLocked(int id) async {
    final used = await widget.store.isUsed(id);
    if (!mounted) return;
    setState(() => _locked = used);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _labelController.dispose();
    _sizeController.dispose();
    _lowController.dispose();
    super.dispose();
  }

  // the input unit that is the base unit itself, like ml for ml
  static InputUnit _baseInputUnit(BaseUnit base) => inputUnitsFor(base).first;

  void _setCountType(CountType type) {
    setState(() {
      _countType = type;
      // number items are pcs only with an exact low level (rule 2)
      if (type == CountType.number) {
        _applyBaseUnit(BaseUnit.pcs);
        _lowMode = LowMode.exact;
      }
    });
  }

  void _setBaseUnit(BaseUnit unit) {
    setState(() => _applyBaseUnit(unit));
  }

  // changing the base unit also resets the unit pickers, so a g item never keeps L picked
  // (no setState inside, the callers wrap it)
  void _applyBaseUnit(BaseUnit unit) {
    _baseUnit = unit;
    _sizeUnit = _baseInputUnit(unit);
    _lowUnit = _baseInputUnit(unit);
  }

  // reads all boxes into a StockItem, or sets _error and gives back null if a number is wrong
  StockItem? _buildItem() {
    double? containerSize;
    if (_isContainer) {
      final typed = readNumber(_sizeController.text);
      if (typed == null) {
        setState(() => _error = 'Type the container size as a number.');
        return null;
      }
      // like 2 L -> 2000 ml
      containerSize = toBaseUnit(typed, _sizeUnit, _baseUnit);
    }

    // empty low level box means 0 (never marked restock)
    final lowText = _lowController.text.trim();
    final lowTyped = lowText.isEmpty ? 0.0 : readNumber(lowText);
    if (lowTyped == null) {
      setState(() => _error = 'Type the low-stock level as a number.');
      return null;
    }
    // containers mode stays a number of containers, exact mode is changed to the base unit
    final lowValue = _lowMode == LowMode.exact
        ? toBaseUnit(lowTyped, _lowUnit, _baseUnit)
        : lowTyped;

    return StockItem(
      id: widget.item?.id,
      name: _nameController.text,
      category: _categoryController.text,
      baseUnit: _baseUnit,
      countType: _countType,
      // number items keep it too, as the piece name
      containerLabel: _labelController.text,
      containerSize: containerSize,
      lowMode: _lowMode,
      lowValue: lowValue,
      // the typed units are saved only to show the amounts the same way again (rule 1)
      // toRow drops them when they are the base unit or not used
      sizeUnit: _isContainer ? _sizeUnit.label : null,
      lowUnit: _lowMode == LowMode.exact ? _lowUnit.label : null,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _archivedMatch = null;
    });

    final item = _buildItem();
    if (item == null) return;

    // same rule check the store does, but shown here before touching the db
    final problem = stockItemProblem(item);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isNew) {
        await widget.store.add(item);
      } else {
        await widget.store.update(item);
      }
      widget.onDone('Saved ${item.name.trim()}.');
    } on NameTakenException catch (e) {
      // archived item with this name: offer restore instead of a duplicate (rule 12)
      setState(() {
        if (e.existing.isArchived) {
          _archivedMatch = e.existing;
        } else {
          _error = 'Another item is already called "${e.existing.name}".';
        }
      });
    } on StockItemException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // archive button: check the recipe rule first, then ask, then archive
  Future<void> _archive() async {
    if (_saving) return;
    final item = widget.item!;
    setState(() {
      _error = null;
      _archivedMatch = null;
    });

    // used in an active recipe = show why in the red box, no dialog
    final problem = await widget.store.archiveProblem(item.id!);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    // showDialog waits until the owner taps a button, true = archive
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archive ${item.name}?'),
        content: const Text(
          'It will be hidden from the list and from new counts. Past counts '
          'and reports keep it. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    // null = closed by tapping outside the dialog, same as cancel
    if (yes != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await widget.store.archive(item.id!);
      widget.onDone('Archived ${item.name}.');
    } on StockItemException catch (e) {
      // a recipe could have been added in between, the store checks again
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // brings back the archived item with its old settings, what was typed here is dropped
  Future<void> _restoreMatch() async {
    final match = _archivedMatch!;
    await widget.store.restore(match.id!);
    widget.onDone('Restored ${match.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // title, archive (only when editing), close
          // archive sits up here since the footer is too narrow for 3 buttons, the dialog still asks first
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isNew ? 'Add stock item' : 'Edit stock item',
                    style: text.titleMedium,
                  ),
                ),
                if (!_isNew)
                  TextButton(
                    onPressed: _saving ? null : _archive,
                    child: const Text('Archive'),
                  ),
                IconButton(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const Divider(),
          // the fields scroll, so the keyboard or a short screen never cuts them off
          // SingleChildScrollView + Column builds every field at once (a ListView only builds what is on screen),
          // fine here since the form is short
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('name_field'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 14),
                  _categoryField(),
                  const SizedBox(height: 18),
                  _countTypeAndUnit(text),
                  const SizedBox(height: 18),
                  if (_isContainer)
                    _containerFields(text)
                  else
                    _pieceNameField(),
                  const SizedBox(height: 18),
                  _lowStockFields(text),
                ],
              ),
            ),
          ),
          // error / restore offer sit outside the scrolling list, right above save,
          // so the owner always sees them after tapping save
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: MessageBox(text: _error!, isError: true),
            ),
          if (_archivedMatch != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _restoreOffer(),
            ),
          const Divider(),
          // cancel + save at the bottom, always visible
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // category box + chips of the categories already used
  Widget _categoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('category_field'),
          controller: _categoryController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category (optional)',
            hintText: 'empty = $defaultCategory',
          ),
        ),
        if (widget.categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Wrap = chips go to the next line when they dont fit
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final category in widget.categories)
                ActionChip(
                  label: Text(category),
                  onPressed: () =>
                      setState(() => _categoryController.text = category),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // count type + base unit choices, greyed out when the item is locked
  Widget _countTypeAndUnit(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Count type', style: text.bodySmall),
        const SizedBox(height: 6),
        // onSelectionChanged null = the buttons are greyed out
        SegmentedButton<CountType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: CountType.container, label: Text('Container')),
            ButtonSegment(value: CountType.number, label: Text('Number')),
          ],
          selected: {_countType},
          onSelectionChanged: _locked
              ? null
              : (picked) => _setCountType(picked.first),
        ),
        const SizedBox(height: 14),
        Text('Base unit', style: text.bodySmall),
        const SizedBox(height: 6),
        SegmentedButton<BaseUnit>(
          showSelectedIcon: false,
          segments: [
            for (final unit in BaseUnit.values)
              ButtonSegment(value: unit, label: Text(unit.name)),
          ],
          selected: {_baseUnit},
          // number items are always pcs, so the unit cant be picked for them
          onSelectionChanged: _locked || !_isContainer
              ? null
              : (picked) => _setBaseUnit(picked.first),
        ),
        if (_locked) ...[
          const SizedBox(height: 8),
          Text(
            'Unit and count type are locked because this item is already in '
            'past counts or recipes.',
            style: text.bodySmall,
          ),
        ],
      ],
    );
  }

  // container label + size (only for container items)
  Widget _containerFields(TextTheme text) {
    // shows the size in the base unit when typed in another unit, like "= 2,000 ml"
    final typed = readNumber(_sizeController.text);
    final showsBase = typed != null && _sizeUnit.factor != 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('label_field'),
          controller: _labelController,
          // redraw so the low-stock word ("bottles") follows the typing
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Container name (optional)',
            hintText: 'like bottle, pack, carton',
          ),
        ),
        const SizedBox(height: 14),
        AmountField(
          fieldKey: const Key('size_field'),
          unitKey: const Key('size_unit'),
          label: 'Size of 1 full container',
          controller: _sizeController,
          units: inputUnitsFor(_baseUnit),
          unit: _sizeUnit,
          onUnitChanged: (unit) => setState(() => _sizeUnit = unit),
          // redraw so the "= 2,000 ml" line follows the typing
          onChanged: (_) => setState(() {}),
        ),
        if (showsBase) ...[
          const SizedBox(height: 4),
          Text(
            '= ${formatWithUnit(toBaseUnit(typed, _sizeUnit, _baseUnit), _baseUnit.name)}',
            style: text.bodySmall,
          ),
        ],
      ],
    );
  }

  // number items: what 1 piece is called on screens, like "pack" (display only, it is still counted in pcs)
  // same db column as the container name, so the box keeps its key
  Widget _pieceNameField() {
    return TextField(
      key: const Key('label_field'),
      controller: _labelController,
      // redraw so the low-stock word ("packs") follows the typing
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'Piece name (optional)',
        hintText: 'like pack, piece. Empty shows pcs',
      ),
    );
  }

  // low-stock level: in containers or an exact amount
  Widget _lowStockFields(TextTheme text) {
    final label = _labelController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Low-stock level', style: text.bodySmall),
        const SizedBox(height: 6),
        if (_isContainer) ...[
          SegmentedButton<LowMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: LowMode.containers,
                label: Text('Containers'),
              ),
              ButtonSegment(value: LowMode.exact, label: Text('Exact amount')),
            ],
            selected: {_lowMode},
            onSelectionChanged: (picked) =>
                setState(() => _lowMode = picked.first),
          ),
          const SizedBox(height: 10),
        ],
        AmountField(
          fieldKey: const Key('low_field'),
          unitKey: const Key('low_unit'),
          label: 'Restock when at or below',
          controller: _lowController,
          // containers mode shows the container name instead of a unit picker
          units: _lowMode == LowMode.containers ? [] : inputUnitsFor(_baseUnit),
          unit: _lowUnit,
          // containers mode: "bottles", a number item with a piece name: "packs"
          fixedSuffix: _lowMode == LowMode.containers
              ? pluralOf(label.isEmpty ? defaultContainerLabel : label)
              : !_isContainer && label.isNotEmpty
              ? pluralOf(label)
              : null,
          onUnitChanged: (unit) => setState(() => _lowUnit = unit),
        ),
      ],
    );
  }

  // yellow box: an archived item already has this name, restore it?
  Widget _restoreOffer() {
    final match = _archivedMatch!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessageBox(
          text:
              '"${match.name}" is an archived item. Restore it with its old '
              'settings instead of adding a new one?',
          isError: false,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _restoreMatch,
            icon: const Icon(Icons.unarchive_outlined, size: 18),
            label: const Text('Restore it'),
          ),
        ),
      ],
    );
  }
}
