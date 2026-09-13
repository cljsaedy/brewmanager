import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'user_repository.dart';

/// Single point of access to the on-device SQLite database.
///
/// This is a singleton: the whole app shares one open connection through
/// [DatabaseHelper.instance]. The file is opened lazily the first time
/// [database] is read and cached after that.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String _fileName = 'brewmanager.db';

  /// Bump this whenever the schema changes after the app is installed.
  /// sqflite will then call [_onUpgrade] instead of [_onCreate].
  static const int _version = 1;

  Database? _db;

  Future<Database> get database async {
    // Reuse the open connection if we already have one.
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _fileName);

    return openDatabase(
      path,
      version: _version,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Runs on every open, before anything else.
  ///
  /// SQLite ignores FOREIGN KEY clauses unless this pragma is turned on for
  /// the connection. Without it, e.g. a batch_deductions row could point at a
  /// transaction that does not exist.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Runs once, the first time the database file is created.
  ///
  /// All twelve tables are created inside one transaction so that a failure
  /// partway through leaves no half-built database on disk.
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      for (final statement in _createStatements) {
        await txn.execute(statement);
      }
      // Seed the one account that exists at install time. Its PIN must be
      // changed on first launch before anything else is accessible.
      await UserRepository.seedDefaultManager(txn);
    });
  }

  /// Runs when [_version] is raised on an already-installed app.
  /// Nothing to migrate yet.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {}

  // ---------------------------------------------------------------------------
  // Schema
  //
  // Table and column names match CLAUDE.md exactly. Conventions:
  //   - booleans are INTEGER 0/1 (SQLite has no boolean type)
  //   - dates and times are ISO-8601 TEXT, e.g. 2026-09-12T14:30:00
  //   - quantities are REAL (millilitres, grams, etc.)
  // ---------------------------------------------------------------------------

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

  // PINs are stored as a hash, never as plain text.
  static const String _createUsers = '''
    CREATE TABLE users (
      user_id    INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL,
      role       TEXT    NOT NULL CHECK (role IN ('Manager', 'Barista')),
      pin_hash   TEXT    NOT NULL,
      is_active  INTEGER NOT NULL DEFAULT 1
    )
  ''';

  // A cafe with rotating shifts reconciles more than once per day, so
  // reconciliation is tied to a session rather than a calendar date.
  static const String _createShiftSessions = '''
    CREATE TABLE shift_sessions (
      shift_id   INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id    INTEGER NOT NULL REFERENCES users(user_id),
      opened_at  TEXT    NOT NULL,
      closed_at  TEXT,
      status     TEXT    NOT NULL CHECK (status IN ('open', 'closed'))
    )
  ''';

  // Deliberately has NO quantity column. Stock lives in inventory_batches.
  static const String _createIngredients = '''
    CREATE TABLE ingredients (
      ingredient_id    INTEGER PRIMARY KEY AUTOINCREMENT,
      name             TEXT    NOT NULL UNIQUE,
      unit_of_measure  TEXT    NOT NULL,
      is_archived      INTEGER NOT NULL DEFAULT 0
    )
  ''';

  // A batch = one expiry date + one container size. This is what FEFO
  // deducts from.
  static const String _createInventoryBatches = '''
    CREATE TABLE inventory_batches (
      batch_id             INTEGER PRIMARY KEY AUTOINCREMENT,
      ingredient_id        INTEGER NOT NULL REFERENCES ingredients(ingredient_id),
      expiry_date          TEXT    NOT NULL,
      container_capacity   REAL    NOT NULL,
      containers_received  INTEGER NOT NULL,
      quantity_remaining   REAL    NOT NULL,
      received_at          TEXT    NOT NULL
    )
  ''';

  static const String _createMenuItems = '''
    CREATE TABLE menu_items (
      menu_item_id   INTEGER PRIMARY KEY AUTOINCREMENT,
      name           TEXT    NOT NULL UNIQUE,
      selling_price  REAL    NOT NULL,
      is_archived    INTEGER NOT NULL DEFAULT 0
    )
  ''';

  // UNIQUE(menu_item_id, ingredient_id) stops a double-tap from adding the
  // same ingredient to a recipe twice, which would deduct it twice on every
  // sale forever.
  static const String _createRecipeBlueprints = '''
    CREATE TABLE recipe_blueprints (
      blueprint_id       INTEGER PRIMARY KEY AUTOINCREMENT,
      menu_item_id       INTEGER NOT NULL REFERENCES menu_items(menu_item_id),
      ingredient_id      INTEGER NOT NULL REFERENCES ingredients(ingredient_id),
      quantity_required  REAL    NOT NULL,
      UNIQUE (menu_item_id, ingredient_id)
    )
  ''';

  // Voids are marked with is_voided, never deleted.
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

  // unit_price_at_sale is a snapshot. Historical reports must read this,
  // never the current price in menu_items.
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

  // One row per (transaction, batch) pair. A sale that draws from two
  // batches writes two rows. This is what lets a void return each amount
  // to the exact batch it came from.
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

  // Declared losses (e.g. a dropped bottle) are kept apart from unexplained
  // variance so the loss chart can tell known incidents from mystery drift.
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

  // Every suggestion is logged so the decision support module can be
  // evaluated: did the suggested item actually sell?
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
