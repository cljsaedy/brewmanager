import 'package:flutter/material.dart';

import '../database/batch_repository.dart';
import '../database/loss_repository.dart';
import '../models/inventory_batch.dart';
import '../session/session.dart';

/// record a spill or dropped container against a specific batch
class DeclareLossScreen extends StatefulWidget {
  const DeclareLossScreen({super.key});

  @override
  State<DeclareLossScreen> createState() => _DeclareLossScreenState();
}

class _DeclareLossScreenState extends State<DeclareLossScreen> {
  final _batches = BatchRepository();
  final _losses = LossRepository();

  List<BatchWithIngredient> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _batches.getAllWithIngredient();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _declare(BatchWithIngredient item) async {
    final user = Session.currentUser;
    if (user == null) return;

    final containers = await showDialog<int>(
      context: context,
      builder: (_) => _LossDialog(item: item),
    );
    if (containers == null) return;

    final deducted = await _losses.declareContainerLost(
      batch: item,
      containersLost: containers,
      userId: user.userId,
    );
    await _reload();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Recorded loss of ${_fmt(deducted)} ${item.unitOfMeasure} '
          '${item.ingredientName}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Declare Container Lost')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? const Center(child: Text('No stock on hand'))
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Pick the batch the spilled or dropped container came from.',
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _list[index];
                          return ListTile(
                            title: Text(item.ingredientName),
                            subtitle: Text(
                              'Expires ${item.batch.expiryDate} · '
                              '${_fmt(item.batch.containerCapacity)} ${item.unitOfMeasure} containers · '
                              '${_fmt(item.batch.quantityRemaining)} ${item.unitOfMeasure} left',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _declare(item),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// container stepper plus a warning of what will be deducted
class _LossDialog extends StatefulWidget {
  const _LossDialog({required this.item});

  final BatchWithIngredient item;

  @override
  State<_LossDialog> createState() => _LossDialogState();
}

class _LossDialogState extends State<_LossDialog> {
  int _containers = 1;

  /// can't lose more containers than the remaining stock could fill
  int get _max => widget.item.wholeContainersLeft;

  /// what will actually come off, clamped the same way the repository clamps it
  double get _deduction {
    final wanted = _containers * widget.item.batch.containerCapacity;
    final left = widget.item.batch.quantityRemaining;
    return wanted > left ? left : wanted;
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.item.unitOfMeasure;

    return AlertDialog(
      title: Text('Containers lost — ${widget.item.ingredientName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _containers > 1
                    ? () => setState(() => _containers--)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '$_containers',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                iconSize: 40,
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _containers < _max
                    ? () => setState(() => _containers++)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'This will deduct ${_fmt(_deduction)} $unit and record it as a declared loss.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _containers),
          child: const Text('Record loss'),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
