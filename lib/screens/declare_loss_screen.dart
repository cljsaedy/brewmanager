import 'package:flutter/material.dart';

import '../database/batch_repository.dart';
import '../database/loss_repository.dart';
import '../database/shift_repository.dart';
import '../logic/expiry_risk.dart';
import '../logic/formatting.dart';
import '../models/declared_loss.dart';
import '../models/inventory_batch.dart';
import '../models/shift.dart';
import '../session/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';
import '../widgets/manager_pin_dialog.dart';
import 'expiry_matrix_screen.dart' show bandColour;

/// record a spill or dropped container against a specific batch
///
/// this is the known incident side of material loss, kept apart from the
/// unexplained drift the closing count finds, so the loss chart can tell a
/// dropped bottle from a mystery
class DeclareLossScreen extends StatefulWidget {
  const DeclareLossScreen({super.key});

  @override
  State<DeclareLossScreen> createState() => _DeclareLossScreenState();
}

class _DeclareLossScreenState extends State<DeclareLossScreen> {
  final _batches = BatchRepository();
  final _losses = LossRepository();
  final _shifts = ShiftRepository();

  List<BatchWithIngredient> _list = [];
  List<DeclaredLoss> _recent = [];
  Shift? _openShift;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _batches.getAllWithIngredient();
    final recent = await _losses.getRecent();
    final openShift = await _shifts.getOpenShift();
    if (!mounted) return;

    // by ingredient then expiry, you go looking for the product you dropped
    // rather than for whatever expires soonest
    list.sort((a, b) {
      final byName = a.ingredientName.toLowerCase().compareTo(
        b.ingredientName.toLowerCase(),
      );
      if (byName != 0) return byName;
      return a.batch.expiryDate.compareTo(b.batch.expiryDate);
    });

    setState(() {
      _list = list;
      _recent = recent;
      _openShift = openShift;
      _loading = false;
    });
  }

  /// reverses a loss recorded by mistake
  ///
  /// needs manager approval, it puts stock back and takes the waste figure down
  Future<void> _undo(DeclaredLoss loss) async {
    final manager = await ManagerPinDialog.show(
      context,
      'Undo the loss of ${quantity(loss.quantityDeducted)} '
      '${loss.unitOfMeasure} ${loss.ingredientName}? '
      'It will be put back on batch #${loss.batchId}.',
    );
    if (manager == null) return;

    await _losses.undoLoss(loss);
    await _reload();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${quantity(loss.quantityDeducted)} ${loss.unitOfMeasure} '
          '${loss.ingredientName} returned to batch #${loss.batchId}',
        ),
      ),
    );
  }

  Future<void> _declare(BatchWithIngredient item) async {
    final user = Session.currentUser;
    if (user == null) return;

    final loss = await showDialog<_LossResult>(
      context: context,
      builder: (_) => _LossDialog(item: item),
    );
    if (loss == null) return;

    final deducted = await _losses.declareContainerLost(
      batch: item,
      containersLost: loss.containers,
      quantityLost: loss.quantity,
      userId: user.userId,
    );
    await _reload();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Recorded a loss of ${quantity(deducted)} ${item.unitOfMeasure} '
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
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No stock on hand',
              message:
                  'There is nothing recorded to declare a loss '
                  'against. Receive stock first.',
            )
          : Column(
              children: [
                _buildHeader(),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ListView.separated(
                          itemCount: _list.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) => _BatchRow(
                            item: _list[index],
                            onTap: () => _declare(_list[index]),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(flex: 2, child: _buildRecent()),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// losses already recorded, with a way to take back a mistake
  Widget _buildRecent() {
    return Container(
      color: AppColors.surfaceSunken,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recorded losses',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Undo one that was recorded by mistake.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _recent.isEmpty
                ? const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Nothing recorded yet',
                    message: 'Losses you declare appear here.',
                  )
                : ListView.separated(
                    itemCount: _recent.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final loss = _recent[index];
                      return ListTile(
                        title: Text(
                          '${quantity(loss.quantityDeducted)} '
                          '${loss.unitOfMeasure} ${loss.ingredientName}',
                        ),
                        subtitle: Text(
                          '${loss.containersLost} '
                          'container${loss.containersLost == 1 ? '' : 's'} · '
                          'batch #${loss.batchId} · '
                          '${_dateTimeLabel(loss.recordedAt)} · '
                          '${loss.recordedBy}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _undo(loss),
                          child: const Text('Undo'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _dateTimeLabel(String iso) {
    final d = DateTime.parse(iso);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _buildHeader() {
    final shift = _openShift;

    return Container(
      width: double.infinity,
      color: AppColors.surfaceSunken,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pick the batch the lost container came from.'),
          const SizedBox(height: AppSpacing.xs),
          // the line between this and the closing count, a whole container that
          // is gone belongs here, a part spill is drift and the count finds it
          Text(
            'For a container that is gone — dropped, spilled or spoiled. '
            'Pouring losses and small spills are found by the closing count '
            'instead.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          // a loss always belongs to a shift, so say which one before recording
          Text(
            shift == null
                ? 'No shift is open — recording a loss will start one.'
                : 'Will be recorded against shift #${shift.shiftId}, '
                      '${shift.userName}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.item, required this.onTap});

  final BatchWithIngredient item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final band = ExpiryRisk.bandFor(item.batch.expiryDate, DateTime.now());
    final unit = item.unitOfMeasure;

    return ListTile(
      leading: Container(
        width: AppSizes.statusBarWidth,
        height: 36,
        decoration: BoxDecoration(
          color: bandColour(band),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(item.ingredientName),
      subtitle: Text(
        '${quantity(item.batch.containerCapacity)} $unit containers · '
        'expires ${item.batch.expiryDate} · batch #${item.batch.batchId}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${quantity(item.batch.quantityRemaining)} $unit',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// what the dialog hands back
class _LossResult {
  const _LossResult(this.containers, this.quantity);

  /// how many containers are gone, this is what the audit's sealed ceiling uses
  final int containers;

  /// how much stock went with them, in the ingredient's own unit
  final double quantity;
}

/// which container was lost
///
/// the feature is for a container that is gone, so the only question is which
/// one, and the amount comes off the records rather than being estimated
///
/// nothing here is adjustable on purpose: a barista cannot know how much was in
/// a carton they just dropped, and asking them to guess would put a made up
/// figure into the records
///
/// if the records were slightly out about what was in the opened container, the
/// difference turns up as unexplained variance at the closing count, which is
/// what that count is for, a part spill is drift and belongs there rather than here
class _LossDialog extends StatefulWidget {
  const _LossDialog({required this.item});

  final BatchWithIngredient item;

  @override
  State<_LossDialog> createState() => _LossDialogState();
}

/// the two kinds of container a batch can hold
enum _Choice { sealed, opened }

class _LossDialogState extends State<_LossDialog> {
  late _Choice _choice = widget.item.impliedSealedCount > 0
      ? _Choice.sealed
      : _Choice.opened;

  /// how many sealed containers were lost, when that is what was picked
  int _sealedLost = 1;

  double get _capacity => widget.item.batch.containerCapacity;

  int get _containersLost => _choice == _Choice.sealed ? _sealedLost : 1;

  /// a sealed container is full, an opened one held whatever the records say,
  /// neither figure is entered by hand
  double get _quantityLost => _choice == _Choice.sealed
      ? _sealedLost * _capacity
      : widget.item.impliedOpenedRemainder;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final unit = item.unitOfMeasure;
    final sealedCount = item.impliedSealedCount;

    return AlertDialog(
      title: const Text('Which container was lost?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.ingredientName} · batch #${item.batch.batchId} · '
                '${quantity(_capacity)} $unit containers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Records show ${quantity(item.batch.quantityRemaining)} $unit '
                'on hand, which is ${_describeShelf(sealedCount, item, unit)}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),

              if (sealedCount > 0)
                _ChoiceCard(
                  selected: _choice == _Choice.sealed,
                  onTap: () => setState(() => _choice = _Choice.sealed),
                  title: 'A sealed container',
                  // sealed means full, so there is nothing to estimate here
                  detail:
                      'Unopened, so it holds a full '
                      '${quantity(_capacity)} $unit',
                  trailing: sealedCount > 1
                      ? _CountStepper(
                          value: _sealedLost,
                          max: sealedCount,
                          enabled: _choice == _Choice.sealed,
                          onChanged: (v) => setState(() => _sealedLost = v),
                        )
                      : null,
                ),

              if (sealedCount > 0 && item.hasOpenedContainer)
                const SizedBox(height: AppSpacing.md),

              if (item.hasOpenedContainer)
                _ChoiceCard(
                  selected: _choice == _Choice.opened,
                  onTap: () => setState(() => _choice = _Choice.opened),
                  title: 'The opened container',
                  // not adjustable, the records are the only figure available
                  // and a guess would be worse than one that is slightly stale
                  detail:
                      'Records say ${quantity(item.impliedOpenedRemainder)} '
                      '$unit was left in it',
                ),

              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  border: Border.all(color: AppColors.danger),
                  borderRadius: BorderRadius.circular(AppSizes.radius),
                ),
                child: Column(
                  children: [
                    Text(
                      '− ${quantity(_quantityLost)} $unit',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dangerText,
                      ),
                    ),
                    Text(
                      'comes off this batch and is recorded as a declared loss',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
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
          onPressed: _quantityLost <= 0
              ? null
              : () => Navigator.pop(
                  context,
                  _LossResult(_containersLost, _quantityLost),
                ),
          child: const Text('Record loss'),
        ),
      ],
    );
  }

  /// plain words for what the records imply is physically on the shelf
  String _describeShelf(
    int sealedCount,
    BatchWithIngredient item,
    String unit,
  ) {
    final parts = <String>[
      if (sealedCount > 0)
        '$sealedCount sealed container${sealedCount == 1 ? '' : 's'}',
      if (item.hasOpenedContainer)
        'one opened container with '
            '${quantity(item.impliedOpenedRemainder)} $unit in it',
    ];
    if (parts.isEmpty) return 'nothing';
    return parts.join(' and ');
  }
}

/// one of the containers that could have been lost
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.detail,
    this.trailing,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.ink.withValues(alpha: 0.05)
              : AppColors.surfaceRaised,
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.hairline,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected ? AppColors.ink : AppColors.outline,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// how many sealed containers, only shown when there is more than one to choose
class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final int max;
  final bool enabled;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          onTap: enabled && value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        _StepButton(
          icon: Icons.add,
          onTap: enabled && value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: Container(
        width: AppSizes.stepper,
        height: AppSizes.stepper,
        decoration: BoxDecoration(
          color: enabled ? AppColors.surfaceRaised : AppColors.surfaceSunken,
          border: Border.all(
            color: enabled ? AppColors.outline : AppColors.hairline,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
        child: Icon(
          icon,
          size: 28,
          color: enabled ? AppColors.ink : AppColors.inkDisabled,
        ),
      ),
    );
  }
}
