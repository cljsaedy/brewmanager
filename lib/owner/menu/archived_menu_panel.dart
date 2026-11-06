import 'package:flutter/material.dart';

import '../../data/menu_item.dart';
import '../../data/menu_item_store.dart';
import '../../logic/formatting.dart';
import '../../theme/app_theme.dart';

// the right side panel for an archived menu item, read only with one restore button
// archived items cant be edited, the owner restores it first then edits it like normal
class ArchivedMenuPanel extends StatefulWidget {
  const ArchivedMenuPanel({
    super.key,
    required this.store,
    required this.item,
    required this.onDone,
    required this.onCancel,
  });

  final MenuItemStore store;
  final MenuItem item;
  // called after restoring, with the message for the snackbar
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;

  @override
  State<ArchivedMenuPanel> createState() => _ArchivedMenuPanelState();
}

class _ArchivedMenuPanelState extends State<ArchivedMenuPanel> {
  // stops a double tap restoring twice
  bool _restoring = false;

  // the recipe comes back as new lines, lines with an archived stock item are left out
  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    final leftOut = await widget.store.restore(widget.item.id!);
    widget.onDone(restoredMessage(widget.item.name, leftOut));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final price = item.priceHint;

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
                  child: Text('Archived menu item', style: text.titleMedium),
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
          // the details scroll in case a short screen cuts them off
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Detail('Name', item.name),
                  _Detail('Category', item.category),
                  _Detail('Price', price == null ? '—' : formatAmount(price)),
                  const SizedBox(height: 8),
                  Text(
                    item.noStock
                        ? 'Restore it to edit it.'
                        : 'Restore it to edit it. Its recipe comes back too.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          // close + restore at the bottom, always visible
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: widget.onCancel,
                  child: const Text('Close'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _restoring ? null : _restore,
                  child: const Text('Restore'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// one "label above value" line in the panel
class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
