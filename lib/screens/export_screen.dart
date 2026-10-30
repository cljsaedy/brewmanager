import 'dart:io';

import 'package:flutter/material.dart';

import '../services/export_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/empty_state.dart';
import 'csv_viewer_screen.dart';

/// writes the data out as csv and pdf files
///
/// this is how the numbers get off the tablet and into the evaluation chapter,
/// so each export says what it is for and how many rows it would contain
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

enum _Range {
  week('Last 7 days', 7),
  month('Last 30 days', 30),
  all('All time', 3650);

  const _Range(this.label, this.days);

  final String label;
  final int days;
}

class _ExportScreenState extends State<ExportScreen> {
  final _service = ExportService();

  _Range _range = _Range.month;
  List<File> _files = [];
  bool _working = false;
  String? _folderPath;
  ({int loss, int reconciliation, int suggestions, int sales, int inventory})?
  _counts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final dir = await _service.exportDirectory();
    final files = await _service.existingExports();
    final now = DateTime.now();
    final counts = await _service.counts(
      from: now.subtract(Duration(days: _range.days)),
      to: now,
    );
    if (!mounted) return;
    setState(() {
      _folderPath = dir.path;
      _files = files;
      _counts = counts;
    });
  }

  /// runs one export and reports where the file went
  Future<void> _run(
    String label,
    Future<File> Function({
      required DateTime from,
      required DateTime to,
      String periodLabel,
    })
    job,
  ) async {
    if (_working) return;
    setState(() => _working = true);

    final now = DateTime.now();
    try {
      final file = await job(
        from: now.subtract(Duration(days: _range.days)),
        to: now,
        // the user's own wording goes into the file name, so the file says
        // what period it covers rather than just when it was written
        periodLabel: _range.label,
      );
      await _reload();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label saved as ${file.uri.pathSegments.last}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Could not export: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;

    return Scaffold(
      appBar: AppBar(title: const Text('Export Data')),
      body: Row(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Row(
                  children: [
                    Text(
                      'Period',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    DropdownButton<_Range>(
                      value: _range,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final r in _Range.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: _working
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() => _range = v);
                              _reload();
                            },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // the two the evaluation chapter actually needs, first
                const _SectionLabel('For the evaluation'),
                _ExportTile(
                  icon: Icons.fact_check_outlined,
                  title: 'Closing counts',
                  subtitle:
                      'Expected against counted per batch. This is the '
                      'accuracy evidence.',
                  rowCount: counts?.reconciliation,
                  enabled: !_working,
                  onTap: () =>
                      _run('Closing counts', _service.exportReconciliationCsv),
                ),
                _ExportTile(
                  icon: Icons.lightbulb_outline,
                  title: 'Suggestions',
                  subtitle:
                      'Each suggestion\'s scores and whether the item '
                      'sold, for testing the weighting.',
                  rowCount: counts?.suggestions,
                  enabled: !_working,
                  onTap: () =>
                      _run('Suggestions', _service.exportSuggestionsCsv),
                ),
                const SizedBox(height: AppSpacing.lg),

                const _SectionLabel('Trading records'),
                _ExportTile(
                  icon: Icons.table_chart_outlined,
                  title: 'Material loss',
                  subtitle:
                      'Every loss with its category, declared or '
                      'unexplained.',
                  rowCount: counts?.loss,
                  enabled: !_working,
                  onTap: () =>
                      _run('Material loss', _service.exportMaterialLossCsv),
                ),
                _ExportTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sales',
                  subtitle: 'Each sold line at the price it sold for.',
                  rowCount: counts?.sales,
                  enabled: !_working,
                  onTap: () => _run('Sales', _service.exportSalesCsv),
                ),
                _ExportTile(
                  icon: Icons.inventory_2_outlined,
                  title: 'Inventory',
                  // says the period does not apply, every other tile on this
                  // screen obeys the filter and this one cannot
                  subtitle:
                      'Every batch with stock left, as it stands right now. '
                      'Ignores the period above.',
                  rowCount: counts?.inventory,
                  enabled: !_working,
                  onTap: () =>
                      _runSnapshot('Inventory', _service.exportInventoryCsv),
                ),
                const SizedBox(height: AppSpacing.lg),

                const _SectionLabel('Readable report'),
                _ExportTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Loss report (PDF)',
                  subtitle:
                      'A one page summary of losses and closing counts, '
                      'for printing or appending to the paper.',
                  rowCount: null,
                  enabled: !_working,
                  onTap: () =>
                      _run('Loss report', _service.exportLossReportPdf),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildFileList()),
        ],
      ),
    );
  }

  /// runs an export that takes no period, and reports where the file went
  ///
  /// separate from [_run] rather than passing dates that get ignored, the
  /// inventory report is a snapshot of what is on the shelf now and naming it
  /// after the filter's period would say something untrue about the file
  Future<void> _runSnapshot(String label, Future<File> Function() job) async {
    if (_working) return;
    setState(() => _working = true);

    try {
      final file = await job();
      await _reload();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label saved as ${file.uri.pathSegments.last}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text('Could not export: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// opens an exported csv in the app, so an export can be checked on the spot
  Future<void> _openCsv(File file) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CsvViewerScreen(file: file)));
  }

  /// says why a pdf can't be opened here
  ///
  /// drawing a pdf needs a renderer, and the pdf package the app uses only
  /// writes them, so opening one in the app would mean another dependency
  /// for a file that is meant to be printed or attached to the paper anyway
  Future<void> _explainPdf(File file) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Opening the report'),
        content: Text(
          'BrewManager can write this report but not display it — reading a '
          'PDF needs a viewer the app does not include.\n\n'
          'Open it with the tablet\'s own Files app, or copy it to a '
          'computer. It is saved as:\n\n'
          '${file.uri.pathSegments.last}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
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
                  'Exported files',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                // the full path, so the files can be found over usb
                Text(
                  _folderPath ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _files.isEmpty
                ? const EmptyState(
                    icon: Icons.folder_outlined,
                    title: 'Nothing exported yet',
                    message:
                        'Files you export are listed here and stay on the '
                        'tablet until you delete them.',
                  )
                : ListView.separated(
                    itemCount: _files.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final stat = file.statSync();
                      final isPdf = file.path.endsWith('.pdf');

                      return ListTile(
                        leading: Icon(
                          isPdf
                              ? Icons.picture_as_pdf_outlined
                              : Icons.table_chart_outlined,
                        ),
                        title: Text(file.uri.pathSegments.last),
                        subtitle: Text(
                          '${_sizeLabel(stat.size)} · '
                          '${_timeLabel(stat.modified)}',
                        ),
                        // csv opens here, a pdf needs a renderer the app does
                        // not carry, see _explainPdf
                        trailing: Icon(
                          isPdf ? Icons.info_outline : Icons.chevron_right,
                        ),
                        onTap: () => isPdf ? _explainPdf(file) : _openCsv(file),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  String _timeLabel(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.rowCount,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// rows this export would write, null when it isn't a row based export
  final int? rowCount;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // an export with nothing in it is still allowed, but say so first
    final isEmpty = rowCount == 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(icon, size: 28, color: AppColors.ink),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (rowCount != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              isEmpty
                                  ? 'nothing in this period'
                                  : '$rowCount row${rowCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isEmpty
                                    ? AppColors.cautionText
                                    : AppColors.inkMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Icon(Icons.download, color: AppColors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
