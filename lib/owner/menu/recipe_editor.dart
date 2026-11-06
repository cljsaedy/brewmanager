import 'package:flutter/material.dart';

import '../../data/menu_item_store.dart';
import '../../data/recipe_store.dart';
import '../../data/stock_item.dart';
import '../../data/stock_item_store.dart';
import '../../logic/formatting.dart';
import '../../logic/units.dart';
import '../../theme/app_theme.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/message_box.dart';

// the recipe part of the menu item panel: the list of lines, and one box to add or change a line
// every change is saved to the db right away, the panel's save button is not needed for these
class RecipeEditor extends StatefulWidget {
  const RecipeEditor({
    super.key,
    required this.recipes,
    required this.stock,
    required this.menuItemId,
    required this.onChanged,
  });

  final RecipeStore recipes;
  final StockItemStore stock;
  final int menuItemId;
  // called after every change with how many lines the recipe has now
  final ValueChanged<int> onChanged;

  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  // null while still loading from the db
  List<RecipeLine>? _lines;
  // active stock items, archived ones never go in a recipe (rule 12)
  List<StockItem> _stockItems = [];

  // the stock item picked to add, null = nothing picked yet
  int? _pickedStockId;
  // the line being changed, null = the box is for adding a new line
  RecipeLine? _editing;
  // which unit the amount is typed in, like oz, changed to the base unit before saving
  InputUnit? _unit;
  final _amountController = TextEditingController();

  String? _error;
  // stops a double tap adding twice
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lines = await widget.recipes.lines(widget.menuItemId);
    final stockItems = await widget.stock.list();
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _stockItems = stockItems;
    });
  }

  // the base unit of the amount being typed, null when no stock item is picked yet
  BaseUnit? get _baseUnit {
    final editing = _editing;
    if (editing != null) return editing.baseUnit;
    for (final item in _stockItems) {
      if (item.id == _pickedStockId) return item.baseUnit;
    }
    return null;
  }

  // stock items not in the recipe yet, one stock item only once per menu item (rule 6)
  List<StockItem> get _addable {
    final lines = _lines ?? [];
    return _stockItems
        .where((item) => !lines.any((line) => line.stockItemId == item.id))
        .toList();
  }

  // the first unit in the list is always the base unit itself
  void _pickStock(int? id) {
    setState(() {
      _pickedStockId = id;
      _error = null;
      final base = _baseUnit;
      _unit = base == null ? null : inputUnitsFor(base).first;
    });
  }

  // tapping a line puts it in the box, in the unit the owner typed it in
  void _startEdit(RecipeLine line) {
    setState(() {
      _editing = line;
      _pickedStockId = null;
      _unit = line.shownUnit;
      _amountController.text = plainNumber(line.shownAmount);
      _error = null;
    });
  }

  // empties the box so it is ready to add a new line
  void _resetBox() {
    setState(() {
      _editing = null;
      _pickedStockId = null;
      _unit = null;
      _amountController.clear();
      _error = null;
    });
  }

  // add button (or update when a line is being changed)
  Future<void> _submit() async {
    if (_busy) return;
    final base = _baseUnit;
    final unit = _unit;
    if (base == null || unit == null) return;

    final typed = readNumber(_amountController.text);
    if (typed == null) {
      setState(() => _error = 'Type the amount as a number.');
      return;
    }
    // like 1 oz -> 29.5735 ml, recipes are always saved in the base unit (rule 1)
    final amount = toBaseUnit(typed, unit, base);
    // the typed unit is saved too so the line can show "6 oz (177.44 ml)"
    // factor 1 = the base unit itself, nothing extra to remember
    final inputUnit = unit.factor == 1 ? null : unit.label;

    setState(() => _busy = true);
    try {
      final editing = _editing;
      if (editing != null) {
        // archives the old line and adds a new one, see RecipeStore (rule 12)
        await widget.recipes.changeAmount(
          editing.id,
          amount,
          inputUnit: inputUnit,
        );
      } else {
        await widget.recipes.addLine(
          widget.menuItemId,
          _pickedStockId!,
          amount,
          inputUnit: inputUnit,
        );
      }
      await _afterChange();
    } on MenuItemException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // the line is archived not deleted, the owner can add the stock item again anytime
  Future<void> _remove(RecipeLine line) async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.recipes.removeLine(line.id);
    await _afterChange();
    if (mounted) setState(() => _busy = false);
  }

  // empties the box, reads the lines again and tells the panel the new line count
  Future<void> _afterChange() async {
    if (!mounted) return;
    _resetBox();
    await _load();
    final lines = _lines;
    if (lines != null) widget.onChanged(lines.length);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lines = _lines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recipe', style: text.titleSmall),
        const SizedBox(height: 2),
        // cancel in the panel does not undo these, so it is said here
        Text('Recipe changes save right away.', style: text.bodySmall),
        const SizedBox(height: 10),
        if (lines == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          for (final line in lines) _lineRow(line),
          if (lines.isEmpty) Text('No lines yet.', style: text.bodySmall),
          const SizedBox(height: 14),
          _box(text),
        ],
      ],
    );
  }

  // one recipe line, tap to change the amount, x to remove
  Widget _lineRow(RecipeLine line) {
    final selected = _editing?.id == line.id;

    return Material(
      color: selected ? AppColors.cream : Colors.transparent,
      child: InkWell(
        onTap: () => _startEdit(line),
        child: Container(
          padding: const EdgeInsets.only(left: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              // name above the amount, "6 oz (177.44 ml)" is too long to share a line in this narrow panel
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.stockName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(line.amountText),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => _remove(line),
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove ${line.stockName}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // the box under the lines: pick a stock item + amount, or the amount of the line being changed
  Widget _box(TextTheme text) {
    final editing = _editing;

    // nothing can be added, and no line is being changed
    if (editing == null && _addable.isEmpty) {
      return Text(
        _stockItems.isEmpty
            ? 'Add stock items first, in the Stock Items tab.'
            : 'Every stock item is already in this recipe.',
        style: text.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editing != null)
          Text('Change ${editing.stockName}', style: text.bodySmall)
        else
          _stockPicker(),
        if (_baseUnit != null) ...[
          const SizedBox(height: 10),
          _amountBox(text),
          const SizedBox(height: 10),
          if (_error != null) ...[
            MessageBox(text: _error!, isError: true),
            const SizedBox(height: 10),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _resetBox, child: const Text('Clear')),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : _submit,
                child: Text(editing != null ? 'Update' : 'Add'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // dropdown of the stock items not in the recipe yet
  Widget _stockPicker() {
    return InputDecorator(
      decoration: const InputDecoration(labelText: 'Add a stock item'),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: const Key('recipe_stock_picker'),
          value: _pickedStockId,
          isExpanded: true,
          isDense: true,
          // a long stock list scrolls inside the menu
          menuMaxHeight: 300,
          items: [
            for (final item in _addable)
              DropdownMenuItem(
                value: item.id,
                child: Text(item.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _pickStock,
        ),
      ),
    );
  }

  // amount box with the unit picker, g items only get g/kg so weight and volume never mix (rule 1)
  Widget _amountBox(TextTheme text) {
    final base = _baseUnit!;
    final unit = _unit!;
    final typed = readNumber(_amountController.text);
    // shows the amount in the base unit when typed in another unit, like "= 29.57 ml"
    final showsBase = typed != null && unit.factor != 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AmountField(
          fieldKey: const Key('recipe_amount_field'),
          unitKey: const Key('recipe_amount_unit'),
          label: 'Amount',
          controller: _amountController,
          units: inputUnitsFor(base),
          unit: unit,
          onUnitChanged: (picked) => setState(() => _unit = picked),
          // redraw so the "= 29.57 ml" line follows the typing
          onChanged: (_) => setState(() {}),
        ),
        if (showsBase) ...[
          const SizedBox(height: 4),
          Text(
            '= ${formatWithUnit(toBaseUnit(typed, unit, base), base.name)}',
            style: text.bodySmall,
          ),
        ],
      ],
    );
  }
}
