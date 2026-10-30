import 'package:flutter/material.dart';

import '../database/user_repository.dart';
import '../services/backup_service.dart';
import '../services/evaluation_scenario_service.dart';
import '../session/session.dart';
import '../widgets/manager_pin_dialog.dart';
import 'change_pin_screen.dart';
import 'pin_entry_screen.dart';

/// loads the fixed starting state the accuracy tests assume
///
/// the tables below are the scenario itself, so the tablet shows the same numbers
/// the printed test instrument refers to
class EvaluationScenarioScreen extends StatefulWidget {
  const EvaluationScenarioScreen({super.key});

  @override
  State<EvaluationScenarioScreen> createState() =>
      _EvaluationScenarioScreenState();
}

class _EvaluationScenarioScreenState extends State<EvaluationScenarioScreen> {
  final _scenario = EvaluationScenarioService();
  final _backups = BackupService();

  bool _working = false;

  Future<void> _load() async {
    if (_working) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Reset to the test scenario?'),
        content: const Text(
          'All sales, deliveries, declared losses, closing counts, suggestions '
          'and shifts will be deleted, and the ingredients, recipes, prices and '
          'batches will be replaced with the fixed set listed on this screen.\n\n'
          'Staff accounts and PINs are left alone.\n\n'
          'A copy of the current database is saved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // wiping trading data needs manager approval, same as a void or a restore
    final manager = await ManagerPinDialog.show(
      context,
      'Reset the database to the fixed test scenario?',
    );
    if (manager == null) return;

    setState(() => _working = true);

    try {
      // so a reset done by mistake can be undone from the backup screen
      final safetyCopy = await _backups.createBackup(
        label: 'Before test scenario',
      );
      await _scenario.load();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Scenario loaded'),
          content: Text(
            'The database now holds exactly the state listed on this screen.\n\n'
            'The previous database was saved as '
            '${safetyCopy.uri.pathSegments.last} and can be put back from '
            'Backup & Restore.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('Could not load the scenario: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// wipes everything including staff and puts the app back to a fresh install
  Future<void> _resetToFirstLaunch() async {
    if (_working) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Clear everything?'),
        content: const Text(
          'The database will be emptied completely — all trading data, all '
          'ingredients, menu items and recipes, and all staff accounts '
          'including yours.\n\n'
          'The app will be back to how it looks on a brand new install: one '
          'Manager with PIN 0000 that must be changed.\n\n'
          'A copy of the current database is saved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final manager = await ManagerPinDialog.show(
      context,
      'Clear the whole database and start over?',
    );
    if (manager == null) return;

    setState(() => _working = true);

    try {
      final safetyCopy = await _backups.createBackup(label: 'Before clearing');
      await _scenario.resetToFirstLaunch();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Database cleared'),
          content: Text(
            'The app is now in its first launch state.\n\n'
            'The previous database was saved as '
            '${safetyCopy.uri.pathSegments.last}, though restoring it needs a '
            'Manager PIN from the database you just cleared.\n\n'
            'Sign in with PIN 0000 — you will be asked to change it.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Start over'),
            ),
          ],
        ),
      );

      // the account that was signed in no longer exists, so the only safe place
      // to go is the first launch screen the installer would see
      await _goToFirstLaunch();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('Could not clear the database: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// mirrors what main() does on a fresh install, straight to the pin change
  Future<void> _goToFirstLaunch() async {
    Session.currentUser = null;

    final manager = await UserRepository().findManagerWithDefaultPin();
    final navigator = Session.navigatorKey.currentState;
    if (navigator == null) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => manager == null
            ? const PinEntryScreen()
            : ChangePinScreen(user: manager),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Tools')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resets the database to a fixed starting state so an '
                          'accuracy test can be run from identical conditions '
                          'every time.',
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Development builds only — this is not present in the '
                          'release build installed at the cafe.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: _working ? null : _load,
                    icon: const Icon(Icons.restart_alt),
                    label: Text(_working ? 'Loading…' : 'Load scenario'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'Menu items and recipes',
            child: Table(
              border: TableBorder.all(color: Colors.black26),
              columnWidths: const {
                0: FlexColumnWidth(1),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(4),
              },
              children: [
                _headerRow(const ['ID', 'Item', 'Price', 'Recipe per serving']),
                for (
                  var i = 0;
                  i < EvaluationScenarioService.menuItems.length;
                  i++
                )
                  _menuRow(i),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'Batches',
            child: Table(
              border: TableBorder.all(color: Colors.black26),
              children: [
                _headerRow(const [
                  'ID',
                  'Ingredient',
                  'Container',
                  'Quantity',
                  'Expires in',
                ]),
                for (
                  var i = 0;
                  i < EvaluationScenarioService.batches.length;
                  i++
                )
                  _batchRow(i),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Total Fresh Milk: '
            '${_fmt(EvaluationScenarioService.totalMilk)} ml across four '
            'batches. FEFO order is batch 1, 2, 3, then 4.\n\n'
            'Batches 3 and 4 share an expiry date with different quantities, so '
            'the smaller one must be depleted first. Caramel Syrup holds exactly '
            'one Caramel Latte, so a second one must be refused. Every batch is '
            'one container, so a sealed count of two is an impossible count.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start over',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Empties the database completely, including staff and '
                          'the sample data, so the app looks like a brand new '
                          'install. Use this to check the first launch '
                          'experience without uninstalling.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onPressed: _working ? null : _resetToFirstLaunch,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Clear everything'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRow _headerRow(List<String> labels) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0x11000000)),
      children: [
        for (final label in labels)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  TableRow _menuRow(int index) {
    final name = EvaluationScenarioService.menuItems.keys.elementAt(index);
    final price = EvaluationScenarioService.menuItems[name]!;
    final recipe = EvaluationScenarioService.recipes[name]!;

    final recipeText = recipe.entries
        .map(
          (e) =>
              '${_fmt(e.value)} '
              '${EvaluationScenarioService.ingredients[e.key]} ${e.key}',
        )
        .join(', ');

    return TableRow(
      children: [
        _cell('${index + 1}'),
        _cell(name),
        _cell('₱${price.toStringAsFixed(0)}'),
        _cell(recipeText),
      ],
    );
  }

  TableRow _batchRow(int index) {
    final batch = EvaluationScenarioService.batches[index];
    final unit = EvaluationScenarioService.ingredients[batch.ingredientName]!;

    return TableRow(
      children: [
        _cell('${index + 1}'),
        _cell(batch.ingredientName),
        _cell('${_fmt(batch.containerCapacity)} $unit'),
        _cell('${_fmt(batch.quantity)} $unit'),
        _cell('${batch.expiresInDays} days'),
      ],
    );
  }

  Widget _cell(String text) =>
      Padding(padding: const EdgeInsets.all(8), child: Text(text));

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
