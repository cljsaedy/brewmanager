import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

// opens the app's sqlite file and makes the tables the first time
// everything is static so the whole app shares one open database
class DatabaseHelper {
  // private constructor so nobody makes a DatabaseHelper object, just use DatabaseHelper.database
  DatabaseHelper._();

  // name of the db file on the tablet
  static const String fileName = 'brewmanager.db';

  // schema version, bump this + add upgrade code when the tables change after the app is in use
  // 1 = first schema, 2 = no menu_sizes table (every size is its own menu item)
  static const int version = 2;

  // the open database, null until first used
  static Database? _db;

  // gets the database, opens it the first time and reuses it after that
  static Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    // the app's private database folder on android
    final folder = await getDatabasesPath();
    final path = join(folder, fileName);

    return openDatabase(
      path,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

  // runs every time the db opens, before anything else
  // sqlite has foreign key checks off by default so we turn them on here
  static Future<void> onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // runs only once, when the db file doesnt exist yet
  // sqflite already wraps onCreate in a transaction, so if one statement fails none of the tables get made
  static Future<void> onCreate(Database db, int version) async {
    // batch = queue up all statements and send them in one go
    final batch = db.batch();
    for (final statement in schemaStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  // runs when the db file on the tablet has an older version than the app, to bring its tables up to date
  // sqflite wraps this in a transaction too, so a failed upgrade changes nothing
  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // 1 -> 2: menu_sizes is gone, recipe_lines and tally_lines point to menu_items now
    // no screen could save menu items, recipes or tallies in version 1, so these 4 tables
    // are always empty and can be dropped and made again (stock items, pin and settings stay)
    if (oldVersion < 2) {
      // drop the tables that point to others first, so the foreign keys never complain
      await db.execute('DROP TABLE IF EXISTS tally_lines');
      await db.execute('DROP TABLE IF EXISTS recipe_lines');
      await db.execute('DROP TABLE IF EXISTS menu_sizes');
      await db.execute('DROP TABLE IF EXISTS menu_items');
      for (final statement in menuTableStatements) {
        await db.execute(statement);
      }
    }
  }

  // closes the db, needed later for restore (close, swap the file, open again)
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
