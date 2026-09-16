import 'package:flutter/material.dart';

import '../database/ingredient_repository.dart' show DuplicateNameException;
import '../database/menu_item_repository.dart';
import '../models/menu_item.dart';

/// manager screen to add, edit and archive menu items
class MenuItemsScreen extends StatefulWidget {
  const MenuItemsScreen({super.key});

  @override
  State<MenuItemsScreen> createState() => _MenuItemsScreenState();
}

class _MenuItemsScreenState extends State<MenuItemsScreen> {
  final _repo = MenuItemRepository();
  List<MenuItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // load from db into state, called after every write
  Future<void> _reload() async {
    final list = await _repo.getActive();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showDialog<_MenuItemFormResult>(
      context: context,
      builder: (_) => const _MenuItemFormDialog(),
    );
    if (result == null) return; // cancelled

    try {
      await _repo.insert(result.name, result.price);
      await _reload();
    } on DuplicateNameException catch (e) {
      _showError('"${e.name}" already exists');
    }
  }

  Future<void> _edit(MenuItem item) async {
    final result = await showDialog<_MenuItemFormResult>(
      context: context,
      builder: (_) => _MenuItemFormDialog(existing: item),
    );
    if (result == null) return;

    try {
      await _repo.update(MenuItem(
        menuItemId: item.menuItemId,
        name: result.name,
        sellingPrice: result.price,
        isArchived: false,
      ));
      await _reload();
    } on DuplicateNameException catch (e) {
      _showError('"${e.name}" already exists');
    }
  }

  Future<void> _archive(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${item.name}?'),
        content: const Text(
          'It will be hidden from the menu but kept for past sales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repo.archive(item.menuItemId);
    await _reload();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Items')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add menu item'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No menu items yet'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle:
                          Text('₱${item.sellingPrice.toStringAsFixed(2)}'),
                      onTap: () => _edit(item),
                      trailing: IconButton(
                        tooltip: 'Archive',
                        icon: const Icon(Icons.archive_outlined),
                        onPressed: () => _archive(item),
                      ),
                    );
                  },
                ),
    );
  }
}

/// what the dialog hands back, null if cancelled
class _MenuItemFormResult {
  const _MenuItemFormResult(this.name, this.price);
  final String name;
  final double price;
}

/// add/edit dialog, pass existing to prefill for edit
class _MenuItemFormDialog extends StatefulWidget {
  const _MenuItemFormDialog({this.existing});

  final MenuItem? existing;

  @override
  State<_MenuItemFormDialog> createState() => _MenuItemFormDialogState();
}

class _MenuItemFormDialogState extends State<_MenuItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late final _priceCtrl = TextEditingController(
    text: widget.existing?.sellingPrice.toStringAsFixed(2),
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _MenuItemFormResult(
        _nameCtrl.text.trim(),
        double.parse(_priceCtrl.text.trim()),
      ),
    );
  }

  // tryParse gives null instead of throwing on bad input like "abc"
  String? _validatePrice(String? v) {
    if (v == null || v.trim().isEmpty) return 'Price is required';
    final parsed = double.tryParse(v.trim());
    if (parsed == null || parsed < 0) return 'Enter a valid price';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(isEdit ? 'Edit menu item' : 'New menu item'),
      // scroll view so the keyboard can't cause an overflow
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Iced Latte 16oz',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                // decimal: true so the numeric keyboard has a "." key
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Selling price',
                  prefixText: '₱ ',
                ),
                validator: _validatePrice,
                onFieldSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
