import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';

/// thrown when the chosen file isn't a sqlite database
///
/// restoring overwrites the live database, so the file is checked before anything
/// is replaced rather than after
class NotADatabaseException implements Exception {}

/// copies the database file out for safe keeping and puts it back again
///
/// the whole system is one sqlite file, so a backup is just a copy of that file,
/// which is one of the upsides of the offline-first design
class BackupService {
  BackupService({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  static const String _folderName = 'BrewManager';
  static const String _backupSubfolder = 'Backups';

  /// every sqlite file starts with these bytes, used to check a file before restoring
  static const List<int> _sqliteMagic = [
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
    0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
  ];

  Future<Directory> backupDirectory() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir =
        Directory(p.join(base.path, _folderName, _backupSubfolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// backups newest first
  Future<List<File>> listBackups() async {
    final dir = await backupDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  /// copies the live database into the backup folder
  Future<File> createBackup({String prefix = 'backup'}) async {
    final sourcePath = await _helper.databaseFilePath();

    // close first so nothing is mid write while the bytes are being copied
    await _helper.close();

    try {
      final dir = await backupDirectory();
      final target = File(p.join(dir.path, '${prefix}_${_stamp()}.db'));
      await File(sourcePath).copy(target.path);
      return target;
    } finally {
      // reopen so the app keeps working whether or not the copy succeeded
      await _helper.database;
    }
  }

  /// replaces the live database with [backup]
  ///
  /// everything recorded since that backup was taken is lost, which is why the
  /// caller asks for a manager pin and a confirmation first
  /// a safety copy of the current database is taken first so a mistaken restore
  /// can itself be undone
  Future<File> restore(File backup) async {
    // check before touching anything, a non database file would leave the app broken
    if (!await _looksLikeSqlite(backup)) {
      throw NotADatabaseException();
    }

    final safetyCopy = await createBackup(prefix: 'before_restore');

    final targetPath = await _helper.databaseFilePath();
    await _helper.close();

    try {
      await backup.copy(targetPath);
    } finally {
      await _helper.database;
    }

    return safetyCopy;
  }

  Future<void> deleteBackup(File backup) async {
    if (await backup.exists()) {
      await backup.delete();
    }
  }

  /// reads just the first 16 bytes and compares them to the sqlite file header
  Future<bool> _looksLikeSqlite(File file) async {
    if (!await file.exists()) return false;

    final handle = await file.open();
    try {
      final header = await handle.read(_sqliteMagic.length);
      if (header.length < _sqliteMagic.length) return false;
      for (var i = 0; i < _sqliteMagic.length; i++) {
        if (header[i] != _sqliteMagic[i]) return false;
      }
      return true;
    } finally {
      await handle.close();
    }
  }

  String _stamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
