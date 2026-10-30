import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/export_repository.dart';
import '../database/loss_analytics_repository.dart';
import '../logic/export_rows.dart';
import '../logic/file_naming.dart';
import '../logic/loss_aggregator.dart';

/// writes csv and pdf files to the device
///
/// files go in the app's external files folder, which needs no runtime permission
/// and can still be reached over usb or a file manager to get them onto a pc
class ExportService {
  ExportService({ExportRepository? exports, LossAnalyticsRepository? losses})
    : _exports = exports ?? ExportRepository(),
      _losses = losses ?? LossAnalyticsRepository();

  final ExportRepository _exports;
  final LossAnalyticsRepository _losses;

  static const String _folderName = 'BrewManager';

  /// where exports land, created on first use
  Future<Directory> exportDirectory() async {
    // external first so the file is reachable from a pc, app documents as a fallback
    final base =
        await getExternalStorageDirectory() ??
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
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  /// how many rows each export would contain for the chosen period
  ///
  /// shown on the buttons so an empty export is obvious before it is written,
  /// rather than after opening the file and finding only a header row
  /// inventory is counted too, but it is a snapshot so its count does not move
  /// with the period
  Future<
    ({int loss, int reconciliation, int suggestions, int sales, int inventory})
  >
  counts({required DateTime from, required DateTime to}) async {
    final loss = await _losses.getLosses(from: from, to: to);
    final reconciliation = await _exports.reconciliationRows(
      from: from,
      to: to,
    );
    final suggestions = await _exports.suggestionRows(from: from, to: to);
    final sales = await _exports.salesRows(from: from, to: to);
    final inventory = await _exports.inventoryRows();

    return (
      loss: loss.length,
      reconciliation: reconciliation.length,
      suggestions: suggestions.length,
      sales: sales.length,
      inventory: inventory.length,
    );
  }

  Future<File> exportMaterialLossCsv({
    required DateTime from,
    required DateTime to,
    String periodLabel = 'All time',
  }) async {
    final records = await _losses.getLosses(from: from, to: to);
    return _writeCsv(
      'Material Loss',
      periodLabel,
      ExportRows.materialLoss(records),
    );
  }

  Future<File> exportReconciliationCsv({
    required DateTime from,
    required DateTime to,
    String periodLabel = 'All time',
  }) async {
    final rows = await _exports.reconciliationRows(from: from, to: to);
    return _writeCsv(
      'Closing Counts',
      periodLabel,
      ExportRows.reconciliation(rows),
    );
  }

  Future<File> exportSuggestionsCsv({
    required DateTime from,
    required DateTime to,
    String periodLabel = 'All time',
  }) async {
    final rows = await _exports.suggestionRows(from: from, to: to);
    return _writeCsv('Suggestions', periodLabel, ExportRows.suggestions(rows));
  }

  Future<File> exportSalesCsv({
    required DateTime from,
    required DateTime to,
    String periodLabel = 'All time',
  }) async {
    final rows = await _exports.salesRows(from: from, to: to);
    return _writeCsv('Sales', periodLabel, ExportRows.sales(rows));
  }

  /// current stock, every batch that still holds something
  ///
  /// takes no date range, unlike the other four: this is what is on the shelf
  /// at the moment the file is written, so a period would mean nothing
  ///
  /// named "Current stock" rather than the filter's period for the same reason
  Future<File> exportInventoryCsv() async {
    final rows = await _exports.inventoryRows();
    return _writeCsv('Inventory', 'Current stock', ExportRows.inventory(rows));
  }

  /// a readable one page summary, for appending to the paper
  Future<File> exportLossReportPdf({
    required DateTime from,
    required DateTime to,
    String periodLabel = 'All time',
  }) async {
    final records = await _losses.getLosses(from: from, to: to);
    final summary = LossAggregator.summary(records);
    final reconciliation = await _exports.reconciliationRows(
      from: from,
      to: to,
    );

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
    final file = await _uniqueFile(dir, 'Loss Report', periodLabel, 'pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  Future<File> _writeCsv(
    String label,
    String periodLabel,
    List<List<Object?>> rows,
  ) async {
    // the encoder quotes anything containing a comma or a quote on its own
    // addBom so excel reads the file as utf-8 instead of mangling accented names
    final csv = const CsvEncoder(addBom: true).convert(rows);

    final dir = await exportDirectory();
    final file = await _uniqueFile(dir, label, periodLabel, 'csv');
    await file.writeAsString(csv);
    return file;
  }

  /// a readable name, with a counter added if that name is already taken
  ///
  /// readable names are not unique on their own, exporting the same thing twice
  /// in a day would collide, and overwriting the first would lose it silently
  Future<File> _uniqueFile(
    Directory dir,
    String label,
    String periodLabel,
    String extension,
  ) async {
    final base = exportFileName(
      label: label,
      periodLabel: periodLabel,
      extension: extension,
      at: DateTime.now(),
    );

    var candidate = File(p.join(dir.path, base));
    var copy = 2;
    while (await candidate.exists()) {
      candidate = File(p.join(dir.path, withCopyNumber(base, copy)));
      copy++;
    }
    return candidate;
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
