import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

// where backups are saved to and picked from, the owner chooses the place each time (rule 13)
// tests pass a fake one, the real file picker needs the tablet
abstract class BackupFiles {
  // asks where to save, gives back false when the owner cancelled
  Future<bool> save(String fileName, Uint8List bytes);

  // asks for a file, gives back its bytes, null when the owner cancelled
  Future<Uint8List?> pick();
}

// the real one, android's own save and open screens through the file_picker package
// on android a picked file is not always a normal path (it can come from google drive),
// so the bytes are read and not the path
class DeviceBackupFiles implements BackupFiles {
  const DeviceBackupFiles();

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final where = await FilePicker.saveFile(
      dialogTitle: 'Save BrewManager backup',
      fileName: fileName,
      bytes: bytes,
    );
    return where != null;
  }

  @override
  Future<Uint8List?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Pick a BrewManager backup',
    );
    return file?.readAsBytes();
  }
}
