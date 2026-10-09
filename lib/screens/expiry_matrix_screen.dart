import 'package:flutter/material.dart';

import '../database/batch_repository.dart';
import '../logic/expiry_risk.dart';
import '../models/inventory_batch.dart';

/// stock on hand, one row per batch, colour coded by how close the expiry is
/// this is the manager's view of what's in the fridge and what needs using up
class ExpiryMatrixScreen extends StatefulWidget {
  const ExpiryMatrixScreen({super.key});

  @override
  State<ExpiryMatrixScreen> createState() => _ExpiryMatrixScreenState();
}

class _ExpiryMatrixScreenState extends State<ExpiryMatrixScreen> {
  final _batches = BatchRepository();

  List<BatchWithIngredient> _withStock = [];
  List<BatchWithIngredient> _depleted = [];
  bool _loading = true;
  bool _showDepleted = false;

  // read once per load so every row on screen is judged against the same date
  late DateTime _today;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await _batches.getAllWithIngredient(includeDepleted: true);
    if (!mounted) return;
    setState(() {
      _today = DateTime.now();
      _withStock =
          all.where((b) => b.batch.quantityRemaining > 0).toList();
      _depleted =
          all.where((b) => b.batch.quantityRemaining <= 0).toList();
      _loading = false;
    });
  }

  /// how many batches sit in each band, for the summary strip
  Map<ExpiryBand, int> get _counts {
    final counts = {ExpiryBand.red: 0, ExpiryBand.yellow: 0, ExpiryBand.green: 0};
    for (final item in _withStock) {
      final band = ExpiryRisk.bandFor(item.batch.expiryDate, _today);
      counts[band] = counts[band]! + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock & Expiry'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          _SummaryStrip(counts: _counts),
          const Divider(height: 1),
          Expanded(
            child: _withStock.isEmpty && _depleted.isEmpty
                ? const Center(child: Text('No batches recorded yet'))
                : ListView(
                    children: [
                      for (final item in _withStock)
                        _BatchRow(item: item, today: _today),

                      if (_depleted.isNotEmpty) ...[
                        const Divider(height: 1),
                        // collapsed by default, kept because empty containers still
                        // physically exist and get counted at the audit
                        ListTile(
                          leading: Icon(
                            _showDepleted
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          title: Text('Depleted batches (${_depleted.length})'),
                          onTap: () =>
                              setState(() => _showDepleted = !_showDepleted),
                        ),
                        if (_showDepleted)
                          for (final item in _depleted)
                            _BatchRow(
                              item: item,
                              today: _today,
                              depleted: true,
                            ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// red/yellow/green counts so the urgent total is visible without reading the list
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.counts});

  final Map<ExpiryBand, int> counts;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Chip(
            band: ExpiryBand.red,
            count: counts[ExpiryBand.red]!,
            label: 'Use now',
          ),
          const SizedBox(width: 12),
          _Chip(
            band: ExpiryBand.yellow,
            count: counts[ExpiryBand.yellow]!,
            label: 'Use this week',
          ),
          const SizedBox(width: 12),
          _Chip(
            band: ExpiryBand.green,
            count: counts[ExpiryBand.green]!,
            label: 'Fine',
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.band, required this.count, required this.label});

  final ExpiryBand band;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = bandColour(band);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(
            '$count',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

/// one batch, with a colour bar on the left showing its band
class _BatchRow extends StatelessWidget {
  const _BatchRow({
    required this.item,
    required this.today,
    this.depleted = false,
  });

  final BatchWithIngredient item;
  final DateTime today;
  final bool depleted;

  @override
  Widget build(BuildContext context) {
    final band = ExpiryRisk.bandFor(item.batch.expiryDate, today);
    final colour = bandColour(band);
    final unit = item.unitOfMeasure;

    return ListTile(
      // colour bar instead of tinting the whole row, easier to scan down the list
      leading: Container(
        width: 8,
        height: 44,
        decoration: BoxDecoration(
          color: depleted ? Theme.of(context).disabledColor : colour,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      title: Text(
        item.ingredientName,
        style: TextStyle(
          color: depleted ? Theme.of(context).disabledColor : null,
        ),
      ),
      subtitle: Text(
        '${item.batch.expiryDate} · '
        '${ExpiryRisk.describe(item.batch.expiryDate, today)}\n'
        '${_fmt(item.batch.containerCapacity)} $unit containers · '
        '${item.batch.containersReceived} received',
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            depleted ? 'empty' : '${_fmt(item.batch.quantityRemaining)} $unit',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: depleted ? Theme.of(context).disabledColor : null,
                ),
          ),
          Text(
            'batch #${item.batch.batchId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// the band colours, kept in one place so the strip and the rows always agree
Color bandColour(ExpiryBand band) {
  switch (band) {
    case ExpiryBand.red:
      return const Color(0xFFC62828);
    case ExpiryBand.yellow:
      return const Color(0xFFF9A825);
    case ExpiryBand.green:
      return const Color(0xFF2E7D32);
  }
}
