import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// shows an exported csv as a table, inside the app
///
/// without this the only way to read an export is to copy the file off the
/// tablet, which is awkward when the point is often just to check an export
/// actually contains what was expected before carrying it away
///
/// no new package needed, the csv dependency already decodes as well as encodes
class CsvViewerScreen extends StatefulWidget {
  const CsvViewerScreen({super.key, required this.file});

  final File file;

  /// rows held in memory at once
  ///
  /// a sales export over a long period can run to thousands of lines, and
  /// building a table that long would stall the tablet for no benefit
  static const int maxRows = 500;

  @override
  State<CsvViewerScreen> createState() => _CsvViewerScreenState();
}

class _CsvViewerScreenState extends State<CsvViewerScreen> {
  List<List<dynamic>> _rows = const [];
  int _totalRows = 0;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var text = await widget.file.readAsString();

      // the exports start with a utf-8 byte order mark so excel reads them
      // correctly, it has to come off before parsing or it lands inside the
      // first column heading
      if (text.startsWith('﻿')) {
        text = text.substring(1);
      }

      final parsed = const CsvDecoder().convert(text);
      if (!mounted) return;
      setState(() {
        _totalRows = parsed.length;
        _rows = parsed.take(CsvViewerScreen.maxRows).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.file.uri.pathSegments.last)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text('Could not read this file: $_error'),
              ),
            )
          : _rows.isEmpty
          ? const Center(child: Text('This file is empty'))
          : Column(
              children: [
                _buildSummary(),
                const Divider(height: 1),
                Expanded(child: _buildTable()),
              ],
            ),
    );
  }

  Widget _buildSummary() {
    // the header row is not data, so it is not counted as one
    final dataRows = _totalRows - 1;
    final shown = _rows.length - 1;
    final truncated = shown < dataRows;

    return Container(
      width: double.infinity,
      color: AppColors.surfaceSunken,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Text(
        truncated
            ? '$dataRows rows · showing the first $shown · '
                  'copy the file off the tablet to read all of it'
            : '$dataRows row${dataRows == 1 ? '' : 's'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// scrolls both ways, these exports are wider than the tablet
  Widget _buildTable() {
    final header = _rows.first;
    final body = _rows.skip(1).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: const WidgetStatePropertyAll(
            AppColors.surfaceSunken,
          ),
          columnSpacing: AppSpacing.xl,
          columns: [
            for (final cell in header)
              DataColumn(
                label: Text(
                  '$cell',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
          rows: [
            for (final row in body)
              DataRow(
                cells: [
                  // pad short rows, a ragged line would otherwise throw
                  for (var i = 0; i < header.length; i++)
                    DataCell(Text(i < row.length ? '${row[i]}' : '')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
