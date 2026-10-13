import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/export_repository.dart';
import '../database/loss_analytics_repository.dart';
import '../logic/export_rows.dart';
import '../logic/loss_aggregator.dart';

/// writes csv and pdf files to the device
///
/// files go in the app's external files folder, which needs no runtime permission
/// and can still be reached over usb or a file manager to get them onto a pc
class ExportService {
  ExportService({
    ExportRepository? exports,
    LossAnalyticsRepository? losses,
  })  : _exports = exports ?? ExportRepository(),
        _losses = losses ?? LossAnalyticsRepository();

  final ExportRepository _exports;
  final LossAnalyticsRepository _losses;

  static const String _folderName = 'BrewManager';

  /// where exports land, created on first use
  Future<Directory> exportDirectory() async {
    // external first so the file is reachable from a pc, app documents as a fallback
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// files already exported, newest first, so the screen can list them
  Future<List<File>> existingExports() async {
    final dir = await exportDirectory();
    final files = dir.listSync().whereType<File>().toList();
    files.sort((a, b) =>
        b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  Future<File> exportMaterialLossCsv({
    required DateTime from,
    required DateTime to,
  }) async {
    final records = await _losses.getLosses(from: from, to: to);
    return _writeCsv('material_loss', ExportRows.materialLoss(records));
  }

  Future<File> exportReconciliationCsv({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _exports.reconciliationRows(from: from, to: to);
    return _writeCsv('reconciliation', ExportRows.reconciliation(rows));
  }

  Future<File> exportSuggestionsCsv({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _exports.suggestionRows(from: from, to: to);
    return _writeCsv('suggestions', ExportRows.suggestions(rows));
  }

  Future<File> exportSalesCsv({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _exports.salesRows(from: from, to: to);
    return _writeCsv('sales', ExportRows.sales(rows));
  }

  /// a readable one page summary, for appending to the paper
  Future<File> exportLossReportPdf({
    required DateTime from,
    required DateTime to,
  }) async {
    final records = await _losses.getLosses(from: from, to: to);
    final summary = LossAggregator.summary(records);
    final reconciliation =
        await _exports.reconciliationRows(from: from, to: to);

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BrewManager — Material Loss Report',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text('Small House Cafe'),
                pw.Text(
                  '${ExportRows.formatDateOnly(from)} to '
                  '${ExportRows.formatDateOnly(to)}',
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Loss by ingredient',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (summary.isEmpty)
            pw.Text('No losses recorded in this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Ingredient',
                'Declared loss',
                'Unexplained',
                'Total',
                'Unit',
              ],
              data: [
                for (final row in summary)
                  [
                    row.ingredientName,
                    _fmt(row.declared),
                    _fmt(row.unexplained),
                    _fmt(row.total),
                    row.unitOfMeasure,
                  ],
              ],
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Declared losses are recorded incidents. Unexplained loss is the gap '
            'found by the closing count. Stock that arrived without being '
            'recorded is a bookkeeping correction and is excluded from these '
            'totals.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Closing counts',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (reconciliation.isEmpty)
            pw.Text('No closing counts recorded in this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Shift',
                'Batch',
                'Ingredient',
                'Expected',
                'Counted',
                'Variance',
                'Type',
              ],
              data: [
                for (final row in reconciliation)
                  [
                    '${row['shift_id']}',
                    '${row['batch_id']}',
                    '${row['ingredient_name']}',
                    _fmt((row['theoretical_quantity'] as num).toDouble()),
                    _fmt((row['audited_quantity'] as num).toDouble()),
                    _fmt((row['variance'] as num).toDouble()),
                    '${row['variance_type']}',
                  ],
              ],
            ),
        ],
      ),
    );

    final dir = await exportDirectory();
    final file = File(p.join(dir.path, _fileName('loss_report', 'pdf')));
    await file.writeAsBytes(await doc.save());
    return file;
  }

  Future<File> _writeCsv(String name, List<List<Object?>> rows) async {
    // the encoder quotes anything containing a comma or a quote on its own
    // addBom so excel reads the file as utf-8 instead of mangling accented names
    final csv = const CsvEncoder(addBom: true).convert(rows);

    final dir = await exportDirectory();
    final file = File(p.join(dir.path, _fileName(name, 'csv')));
    await file.writeAsString(csv);
    return file;
  }

  /// timestamped so an export never silently overwrites an earlier one
  String _fileName(String name, String extension) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${name}_$stamp.$extension';
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
