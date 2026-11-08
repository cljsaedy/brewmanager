import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/backup_files.dart';
import 'package:brewmanager/data/backup_store.dart';
import 'package:brewmanager/data/database_helper.dart';
import 'package:brewmanager/data/email_settings_store.dart';
import 'package:brewmanager/data/owner_pin_store.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/owner/settings/settings_tab.dart';
import 'package:brewmanager/security/key_store.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

// a fake save and open place, nothing touches the tablet's files
class FakeBackupFiles implements BackupFiles {
  // what was saved, null = nothing
  String? savedName;
  Uint8List? savedBytes;
  // false = the owner cancels the save screen
  bool saveAnswer = true;
  // what the open screen gives back, null = cancelled
  Uint8List? toPick;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    if (!saveAnswer) return false;
    savedName = fileName;
    savedBytes = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => toPick;
}

// the test db is in memory, so it has no file to copy, this gives fixed bytes instead
class FakeBackupStore extends BackupStore {
  FakeBackupStore(super.db, {super.clock});

  @override
  Future<({Uint8List bytes, String? oldTime})> snapshot() async {
    final oldTime = await lastBackup();
    await super.undoSnapshot('2026-11-09T07:15:00.000Z');
    return (bytes: Uint8List.fromList([1, 2, 3]), oldTime: oldTime);
  }
}

void main() {
  late Database db;
  late FakeBackupFiles files;
  late OwnerPinStore pins;
  // the bytes the restore fake got, null = restore never ran
  Uint8List? restored;
  // a real brewmanager db file as bytes, for restore
  late Uint8List backupBytes;

  setUpAll(() async {
    sqfliteFfiInit();
    // BackupStore.check opens the picked file with the app's normal sqlite, on the pc that is ffi
    databaseFactory = databaseFactoryFfiNoIsolate;
    final folder = await Directory.systemTemp.createTemp('brewmanager_restore');
    final path = '${folder.path}${Platform.pathSeparator}backup.db';
    final made = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.version,
        onConfigure: DatabaseHelper.onConfigure,
        onCreate: DatabaseHelper.onCreate,
        singleInstance: false,
      ),
    );
    await made.insert('app_settings', {
      'key': BackupStore.lastBackupKey,
      'value': '2026-11-01T07:00:00.000Z',
    });
    await made.close();
    backupBytes = await File(path).readAsBytes();
    await folder.delete(recursive: true);
  });

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    files = FakeBackupFiles();
    pins = OwnerPinStore(db);
    restored = null;
  });

  tearDown(() async {
    await db.close();
  });

  // real file and db work only moves on while the test waits in real time,
  // and each step (temp file, write, open, read) needs its own wait, so it waits in short rounds
  Future<void> waitForDb(WidgetTester tester) async {
    for (var round = 0; round < 15; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    useTabletScreen(tester);
    await pins.setPin('1234');
    await tester.pumpWidget(
      BrewManagerApp(
        home: Scaffold(
          body: SettingsTab(
            store: EmailSettingsStore(db, MemoryKeyStore()),
            pins: pins,
            backup: FakeBackupStore(db),
            files: files,
            restoreDatabase: (bytes) async => restored = bytes,
          ),
        ),
      ),
    );
    await waitForDb(tester);
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.byKey(Key('pin_key_$digit')));
      await tester.pump();
    }
    await waitForDb(tester);
  }

  Future<void> tapAndWait(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await waitForDb(tester);
  }

  testWidgets('change pin: no old pin asked, the new one works', (
    tester,
  ) async {
    await openSettings(tester);

    await tapAndWait(tester, 'change_pin');
    expect(find.text('New owner PIN'), findsOneWidget);
    await typePin(tester, '5678');
    await typePin(tester, '5678');
    expect(find.text('Save your recovery code'), findsOneWidget);
    await tester.tap(find.text('I saved it'));
    await waitForDb(tester);

    // back on settings
    expect(find.byKey(const Key('change_pin')), findsOneWidget);
    expect(find.text('PIN changed.'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await pins.checkPin('5678'), isTrue);
      expect(await pins.checkPin('1234'), isFalse);
    });
  });

  testWidgets('a new recovery code is shown once, the pin stays', (
    tester,
  ) async {
    await openSettings(tester);

    await tapAndWait(tester, 'new_recovery_code');
    await tapAndWait(tester, 'confirm_new_code');
    expect(find.text('Save your recovery code'), findsOneWidget);
    final code = tester.widget<SelectableText>(find.byType(SelectableText));
    await tester.tap(find.text('I saved it'));
    await waitForDb(tester);

    expect(find.text('New recovery code made.'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await pins.checkRecoveryCode(code.data!), isTrue);
      expect(await pins.checkPin('1234'), isTrue);
    });
  });

  testWidgets('back up saves the file and shows the date', (tester) async {
    await openSettings(tester);
    expect(find.text('Last backup: never.'), findsOneWidget);

    await tapAndWait(tester, 'back_up');

    expect(files.savedName, startsWith('brewmanager-backup-'));
    expect(files.savedName, endsWith('.db'));
    expect(find.text('Last backup: never.'), findsNothing);
  });

  testWidgets('a cancelled back up keeps "never"', (tester) async {
    files.saveAnswer = false;
    await openSettings(tester);

    await tapAndWait(tester, 'back_up');

    expect(files.savedName, isNull);
    expect(find.text('Last backup: never.'), findsOneWidget);
  });

  testWidgets('restore asks with the backup date, then replaces', (
    tester,
  ) async {
    files.toPick = backupBytes;
    await openSettings(tester);

    await tapAndWait(tester, 'restore');

    expect(
      find.textContaining(
        'This will replace all current data with the backup from',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Sun, Nov 1'), findsOneWidget);
    await tapAndWait(tester, 'confirm_restore');

    expect(restored, backupBytes);
    expect(find.textContaining('Backup restored.'), findsOneWidget);
  });

  testWidgets('restore cancelled at the question changes nothing', (
    tester,
  ) async {
    files.toPick = backupBytes;
    await openSettings(tester);

    await tapAndWait(tester, 'restore');
    await tester.tap(find.text('Cancel'));
    await waitForDb(tester);

    expect(restored, isNull);
  });

  testWidgets('a file that is not a backup is refused', (tester) async {
    files.toPick = Uint8List.fromList('not a db'.codeUnits);
    await openSettings(tester);

    await tapAndWait(tester, 'restore');

    expect(restored, isNull);
    expect(
      find.text(
        'That file is not a BrewManager backup, so nothing was changed.',
      ),
      findsOneWidget,
    );
  });
}
