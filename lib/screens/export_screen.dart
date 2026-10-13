import 'dart:io';

import 'package:flutter/material.dart';

import '../services/export_service.dart';

/// writes the data out as csv and pdf files for the evaluation chapter
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

  @override
  void initState() {
    super.initState();
    _reloadFiles();
  }

  Future<void> _reloadFiles() async {
    final dir = await _service.exportDirectory();
    final files = await _service.existingExports();
    if (!mounted) return;
    setState(() {
      _folderPath = dir.path;
      _files = files;
    });
  }

  /// runs one export and reports where the file went
  Future<void> _run(
    String label,
    Future<File> Function({required DateTime from, required DateTime to}) job,
  ) async {
    if (_working) return;
    setState(() => _working = true);

    final now = DateTime.now();
    try {
      final file = await job(
        from: now.subtract(Duration(days: _range.days)),
        to: now,
      );
      await _reloadFiles();
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
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text('Could not export: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Data')),
      body: Row(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    const Text('Period: '),
                    const SizedBox(width: 8),
                    DropdownButton<_Range>(
                      value: _range,
                      items: [
                        for (final r in _Range.values)
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: _working
                          ? null
                          : (v) {
                              if (v != null) setState(() => _range = v);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ExportTile(
                  icon: Icons.table_chart_outlined,
                  title: 'Material loss (CSV)',
                  subtitle:
                      'Every loss with its category, declared or unexplained.',
                  enabled: !_working,
                  onTap: () => _run(
                    'Material loss',
                    _service.exportMaterialLossCsv,
                  ),
                ),
                _ExportTile(
                  icon: Icons.fact_check_outlined,
                  title: 'Closing counts (CSV)',
                  subtitle:
                      'Expected against counted per batch. This is the accuracy evidence.',
                  enabled: !_working,
                  onTap: () => _run(
                    'Closing counts',
                    _service.exportReconciliationCsv,
                  ),
                ),
                _ExportTile(
                  icon: Icons.lightbulb_outline,
                  title: 'Suggestions (CSV)',
                  subtitle:
                      'Scores and whether the item sold, for testing the weighting.',
                  enabled: !_working,
                  onTap: () => _run(
                    'Suggestions',
                    _service.exportSuggestionsCsv,
                  ),
                ),
                _ExportTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Sales (CSV)',
                  subtitle: 'Each sold line at the price it sold for.',
                  enabled: !_working,
                  onTap: () => _run('Sales', _service.exportSalesCsv),
                ),
                const Divider(height: 32),
                _ExportTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'Loss report (PDF)',
                  subtitle:
                      'A readable summary of losses and closing counts.',
                  enabled: !_working,
                  onTap: () => _run(
                    'Loss report',
                    _service.exportLossReportPdf,
                  ),
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

  Widget _buildFileList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exported files',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
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
              ? const Center(child: Text('Nothing exported yet'))
              : ListView.separated(
                  itemCount: _files.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    final stat = file.statSync();
                    return ListTile(
                      leading: Icon(
                        file.path.endsWith('.pdf')
                            ? Icons.picture_as_pdf_outlined
                            : Icons.table_chart_outlined,
                      ),
                      title: Text(file.uri.pathSegments.last),
                      subtitle: Text(
                        '${_sizeLabel(stat.size)} · '
                        '${_timeLabel(stat.modified)}',
                      ),
                    );
                  },
                ),
        ),
      ],
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

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.download),
        enabled: enabled,
        onTap: onTap,
      ),
    );
  }
}
