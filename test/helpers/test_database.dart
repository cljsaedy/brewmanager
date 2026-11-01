import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/database_helper.dart';

// makes a fresh empty db in memory with the app's real schema, for tests on the pc
// noIsolate = run sqlite on the same thread as the test, needed inside widget tests
// (widget tests use a fake clock and cant wait on another thread)
Future<Database> openTestDatabase({bool noIsolate = false}) {
  sqfliteFfiInit();
  final factory = noIsolate ? databaseFactoryFfiNoIsolate : databaseFactoryFfi;

  return factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: DatabaseHelper.version,
      onConfigure: DatabaseHelper.onConfigure,
      onCreate: DatabaseHelper.onCreate,
      // false = dont reuse the db from the last test
      singleInstance: false,
    ),
  );
}
