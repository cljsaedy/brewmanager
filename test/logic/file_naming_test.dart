import 'package:flutter_test/flutter_test.dart';

import 'package:brewmanager/logic/file_naming.dart';

void main() {
  final at = DateTime(2026, 10, 17, 22, 5);

  group('exportFileName', () {
    test('says what it holds and over what period', () {
      expect(
        exportFileName(
          label: 'Closing Counts',
          periodLabel: 'Last 30 days',
          extension: 'csv',
          at: at,
        ),
        'Closing Counts (Last 30 days) 2026-10-17.csv',
      );
    });

    test('pads single digit dates so names sort correctly', () {
      expect(
        exportFileName(
          label: 'Sales',
          periodLabel: 'All time',
          extension: 'csv',
          at: DateTime(2026, 1, 2),
        ),
        'Sales (All time) 2026-01-02.csv',
      );
    });

    test('works for the pdf report too', () {
      expect(
        exportFileName(
          label: 'Loss Report',
          periodLabel: 'Last 7 days',
          extension: 'pdf',
          at: at,
        ),
        'Loss Report (Last 7 days) 2026-10-17.pdf',
      );
    });
  });

  group('backupFileName', () {
    test('includes the time, several can be taken in a day', () {
      expect(
        backupFileName(label: 'Backup', at: at),
        'Backup 2026-10-17 22-05.db',
      );
    });

    test('a safety copy says what it was taken before', () {
      expect(
        backupFileName(label: 'Before restore', at: at),
        'Before restore 2026-10-17 22-05.db',
      );
    });

    test('midnight pads to 00-00 rather than 0-0', () {
      expect(
        backupFileName(label: 'Backup', at: DateTime(2026, 10, 17)),
        'Backup 2026-10-17 00-00.db',
      );
    });
  });

  group('withCopyNumber', () {
    test('goes before the extension, not after it', () {
      expect(
        withCopyNumber('Sales (Last 7 days) 2026-10-17.csv', 2),
        'Sales (Last 7 days) 2026-10-17 (2).csv',
      );
    });

    test('handles a name that already contains dots', () {
      expect(
        withCopyNumber('Backup 2026-10-17 22-05.db', 3),
        'Backup 2026-10-17 22-05 (3).db',
      );
    });

    test('a name with no extension still gets a number', () {
      expect(withCopyNumber('report', 2), 'report (2)');
    });
  });
}
