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
  // 1 = first schema, 2 = no menu_sizes table (every size is its own menu item),
  // 3 = recipe_lines.input_unit (the unit the owner typed),
  // 4 = stock_items.needs_opening_count and count_lines.is_opening (opening count, rule 3),
  // 5 = day_results.actual_qty can be empty (an opening count has no usage, rule 7)
  // 6 = corrections.target can be 'day' too (day note corrections, rule 4)
  // 7 = stock_items.size_unit and low_unit (the unit the owner typed, display only)
  static const int version = 7;

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
    } else if (oldVersion < 3) {
      // 2 -> 3: recipe lines remember the unit the owner typed
      // "else" because the 1 -> 2 part above already makes recipe_lines with this column,
      // adding it again would fail
      // ADD COLUMN keeps every row, old lines get null = shown in the base unit
      await db.execute(
        'ALTER TABLE recipe_lines ADD COLUMN input_unit TEXT '
        '$recipeInputUnitCheck',
      );
    }

    // 3 -> 4: the opening count flags
    // not in the "else" above since no earlier step made these 2 tables again, every old db needs this
    // ADD COLUMN keeps every row, old rows get 0 = not an opening count
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE stock_items ADD COLUMN $stockNeedsOpeningColumn',
      );
      await db.execute(
        'ALTER TABLE count_lines ADD COLUMN $lineIsOpeningColumn',
      );
    }

    // 4 -> 5: day_results.actual_qty can be empty
    // sqlite cant change a column's rules, so the table gets made again
    // it is always empty here, nothing saves to it before submit exists in feature 7
    if (oldVersion < 5) {
      await db.execute('DROP TABLE IF EXISTS day_results');
      await db.execute(dayResultsTable);
    }

    // 5 -> 6: corrections.target can be 'day'
    // same as above, sqlite cant change a CHECK rule so the table gets made again
    // it is always empty here, nothing saves a correction before feature 8
    // dropping the table drops its index too, so the list makes both again
    if (oldVersion < 6) {
      await db.execute('DROP TABLE IF EXISTS corrections');
      for (final statement in correctionsTableStatements) {
        await db.execute(statement);
      }
    }

    // 6 -> 7: stock items remember the unit the owner typed the size and low level in
    // ADD COLUMN keeps every row, old items get null = shown in the base unit like before
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE stock_items ADD COLUMN $stockSizeUnitColumn',
      );
      await db.execute(
        'ALTER TABLE stock_items ADD COLUMN $stockLowUnitColumn',
      );
    }
  }

  // closes the db, needed later for restore (close, swap the file, open again)
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
