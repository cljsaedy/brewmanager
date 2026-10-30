import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'dev_seed.dart';
import 'user_repository.dart';

/// single access point to the sqlite db, whole app shares one connection
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _fileName = 'brewmanager.db';

  /// bump this when the schema changes after install, sqflite then runs _onUpgrade
  ///
  /// 2 added menu_items.is_ingredient_tracked, which separates drinks made from
  /// tracked ingredients from food sold as a whole unit, and three columns on
  /// inventory_batches recording who last corrected a batch's figures
  static const int _version = 2;

  Database? _db;

  Future<Database> get database async {
    // reuse the open connection if there is one
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  /// full path of the db file, needed by backup and restore
  Future<String> databaseFilePath() async {
    final dir = await getDatabasesPath();
    return p.join(dir, _fileName);
  }

  /// closes the connection so the file can be copied or replaced safely
  ///
  /// sqlite can be caught mid write if the file is copied while open, so backup and
  /// restore both close first, the next read of [database] reopens it
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final path = await databaseFilePath();

    return openDatabase(
      path,
      version: _version,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// runs on every open, sqlite ignores FOREIGN KEY unless this is on
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// runs once when the db file is first created, makes all 12 tables
  Future<void> _onCreate(Database db, int version) async {
    // one transaction so a failure halfway doesn't leave a half built db
    await db.transaction((txn) async {
      for (final statement in _createStatements) {
        await txn.execute(statement);
      }
      // seed the only account that exists at install, pin must be changed on first launch
      await UserRepository.seedDefaultManager(txn);

      // kDebugMode is true for flutter run and false for a release build, so the cafe's
      // installed app starts empty while development installs get test data
      if (kDebugMode) {
        await DevSeed.run(txn);
      }
    });
  }

  /// runs when _version goes up on an installed app
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // existing menu items are all drinks, so they default to tracked
      await db.execute(
        'ALTER TABLE menu_items '
        'ADD COLUMN is_ingredient_tracked INTEGER NOT NULL DEFAULT 1',
      );

      // all nullable with no default, a batch that was never corrected simply
      // has nothing in these, which is also what sqlite requires for a column
      // added with a REFERENCES clause
      await db.execute(
        'ALTER TABLE inventory_batches '
        'ADD COLUMN corrected_by INTEGER REFERENCES users(user_id)',
      );
      await db.execute(
        'ALTER TABLE inventory_batches ADD COLUMN corrected_at TEXT',
      );
      await db.execute(
        'ALTER TABLE inventory_batches ADD COLUMN previous_quantity REAL',
      );
    }
  }

  // schema, names match CLAUDE.md exactly
  // booleans are INTEGER 0/1 since sqlite has no bool
  // dates are ISO-8601 TEXT like 2026-09-12T14:30:00 so they sort right
  // quantities are REAL (ml, grams, etc)

  static const List<String> _createStatements = [
    _createUsers,
    _createShiftSessions,
    _createIngredients,
    _createInventoryBatches,
    _createMenuItems,
    _createRecipeBlueprints,
    _createTransactions,
    _createTransactionItems,
    _createBatchDeductions,
    _createReconciliationLogs,
    _createLossEvents,
    _createSuggestionLogs,
  ];

  // pin_hash is a salted hash, never the plain pin
  static const String _createUsers = '''
    CREATE TABLE users (
      user_id    INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL,
      role       TEXT    NOT NULL CHECK (role IN ('Manager', 'Barista')),
      pin_hash   TEXT    NOT NULL,
      is_active  INTEGER NOT NULL DEFAULT 1
    )
  ''';

  // shifts instead of dates since a cafe can reconcile more than once a day
  static const String _createShiftSessions = '''
    CREATE TABLE shift_sessions (
      shift_id   INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id    INTEGER NOT NULL REFERENCES users(user_id),
      opened_at  TEXT    NOT NULL,
      closed_at  TEXT,
      status     TEXT    NOT NULL CHECK (status IN ('open', 'closed'))
    )
  ''';

  // no quantity column on purpose, stock lives in inventory_batches
  static const String _createIngredients = '''
    CREATE TABLE ingredients (
      ingredient_id    INTEGER PRIMARY KEY AUTOINCREMENT,
      name             TEXT    NOT NULL UNIQUE,
      unit_of_measure  TEXT    NOT NULL,
      is_archived      INTEGER NOT NULL DEFAULT 0
    )
  ''';

  // a batch = one expiry date + one container size, this is what FEFO deducts from
  //
  // the last three columns record a correction to figures that were entered
  // wrongly at receiving, following the same pattern as transactions.voided_by:
  // the actor is recorded on the row that was affected
  //
  // previous_quantity is kept because an expiry or capacity mistake is
  // self-evident from the corrected figure, whereas a quantity change could
  // hide waste, so the before value is the one worth keeping
  //
  // only the most recent correction is kept, a batch corrected twice loses the
  // earlier before-value, which is a stated limitation of the design
  static const String _createInventoryBatches = '''
    CREATE TABLE inventory_batches (
      batch_id             INTEGER PRIMARY KEY AUTOINCREMENT,
      ingredient_id        INTEGER NOT NULL REFERENCES ingredients(ingredient_id),
      expiry_date          TEXT    NOT NULL,
      container_capacity   REAL    NOT NULL,
      containers_received  INTEGER NOT NULL,
      quantity_remaining   REAL    NOT NULL,
      received_at          TEXT    NOT NULL,
      corrected_by         INTEGER REFERENCES users(user_id),
      corrected_at         TEXT,
      previous_quantity    REAL
    )
  ''';

  // is_ingredient_tracked separates a drink, which is made from ingredients the
  // system deducts and audits, from prepared food sold as a whole unit
  //
  // chapter 1's scope says food items can be sold through the pos but are not
  // tracked at ingredient level, and without this column the app can't tell a
  // food item apart from a drink whose recipe someone forgot to set
  static const String _createMenuItems = '''
    CREATE TABLE menu_items (
      menu_item_id           INTEGER PRIMARY KEY AUTOINCREMENT,
      name                   TEXT    NOT NULL UNIQUE,
      selling_price          REAL    NOT NULL,
      is_archived            INTEGER NOT NULL DEFAULT 0,
      is_ingredient_tracked  INTEGER NOT NULL DEFAULT 1
    )
  ''';

  // UNIQUE stops a double tap adding the same ingredient twice (would deduct twice forever)
  static const String _createRecipeBlueprints = '''
    CREATE TABLE recipe_blueprints (
      blueprint_id       INTEGER PRIMARY KEY AUTOINCREMENT,
      menu_item_id       INTEGER NOT NULL REFERENCES menu_items(menu_item_id),
      ingredient_id      INTEGER NOT NULL REFERENCES ingredients(ingredient_id),
      quantity_required  REAL    NOT NULL,
      UNIQUE (menu_item_id, ingredient_id)
    )
  ''';

  // voids are marked with is_voided, never deleted
  static const String _createTransactions = '''
    CREATE TABLE transactions (
      transaction_id        INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id              INTEGER NOT NULL REFERENCES shift_sessions(shift_id),
      transaction_datetime  TEXT    NOT NULL,
      total_amount          REAL    NOT NULL,
      is_voided             INTEGER NOT NULL DEFAULT 0,
      voided_by             INTEGER REFERENCES users(user_id)
    )
  ''';

  // unit_price_at_sale is a snapshot, reports read this not menu_items so price edits don't rewrite history
  static const String _createTransactionItems = '''
    CREATE TABLE transaction_items (
      transaction_item_id  INTEGER PRIMARY KEY AUTOINCREMENT,
      transaction_id       INTEGER NOT NULL REFERENCES transactions(transaction_id),
      menu_item_id         INTEGER NOT NULL REFERENCES menu_items(menu_item_id),
      quantity             INTEGER NOT NULL,
      unit_price_at_sale   REAL    NOT NULL,
      line_total           REAL    NOT NULL
    )
  ''';

  // one row per (transaction, batch), a sale from 2 batches = 2 rows, this is what lets void put stock back in the exact batch
  static const String _createBatchDeductions = '''
    CREATE TABLE batch_deductions (
      deduction_id       INTEGER PRIMARY KEY AUTOINCREMENT,
      transaction_id     INTEGER NOT NULL REFERENCES transactions(transaction_id),
      batch_id           INTEGER NOT NULL REFERENCES inventory_batches(batch_id),
      quantity_deducted  REAL    NOT NULL
    )
  ''';

  static const String _createReconciliationLogs = '''
    CREATE TABLE reconciliation_logs (
      reconciliation_id     INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id              INTEGER NOT NULL REFERENCES shift_sessions(shift_id),
      batch_id              INTEGER NOT NULL REFERENCES inventory_batches(batch_id),
      theoretical_quantity  REAL    NOT NULL,
      audited_quantity      REAL    NOT NULL,
      variance              REAL    NOT NULL,
      variance_type         TEXT    NOT NULL CHECK (
        variance_type IN ('unexplained', 'declared_loss', 'unrecorded_receiving')
      )
    )
  ''';

  // declared losses (dropped bottle) kept apart from unexplained variance so the chart can tell them apart
  static const String _createLossEvents = '''
    CREATE TABLE loss_events (
      loss_event_id      INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id           INTEGER NOT NULL REFERENCES shift_sessions(shift_id),
      batch_id           INTEGER NOT NULL REFERENCES inventory_batches(batch_id),
      containers_lost    INTEGER NOT NULL,
      quantity_deducted  REAL    NOT NULL,
      recorded_at        TEXT    NOT NULL
    )
  ''';

  // every suggestion is logged so we can check later if the suggested item actually sold
  static const String _createSuggestionLogs = '''
    CREATE TABLE suggestion_logs (
      suggestion_id      INTEGER PRIMARY KEY AUTOINCREMENT,
      shift_id           INTEGER NOT NULL REFERENCES shift_sessions(shift_id),
      menu_item_id       INTEGER NOT NULL REFERENCES menu_items(menu_item_id),
      batch_id           INTEGER NOT NULL REFERENCES inventory_batches(batch_id),
      expiry_risk_score  REAL    NOT NULL,
      popularity_score   REAL    NOT NULL,
      combined_score     REAL    NOT NULL,
      was_accepted       INTEGER NOT NULL DEFAULT 0,
      suggested_at       TEXT    NOT NULL
    )
  ''';
}
