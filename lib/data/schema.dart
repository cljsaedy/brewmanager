// all the CREATE TABLE / CREATE INDEX statements for the database, run once when the db file is first made
//
// notes for every table:
// - quantities are REAL in the stock item's base unit (g, ml or pcs)
// - true/false columns are INTEGER 0 or 1 since sqlite has no boolean type
// - timestamps are ISO 8601 text in UTC like 2026-11-01T05:30:00.000Z so they sort/compare right as text
// - dates are YYYY-MM-DD text
// - CHECK (...) = sqlite refuses to save a row that breaks the rule
// - REFERENCES other_table(id) = foreign key, the id has to exist in that table
// - COLLATE NOCASE = "Milk" and "milk" are treated as the same when comparing
const List<String> schemaStatements = [
  // simple key/value settings: owner email, sender email, pin hash + salt, last backup date, first count date
  // api keys are NOT here, they go in secure storage so a db backup never has them
  '''
  CREATE TABLE app_settings (
    key   TEXT PRIMARY KEY,
    value TEXT
  )
  ''',

  // things that get counted, like milk, caramel syrup, cups, fries packs
  // name has to be trimmed (no spaces at the ends), not empty, and unique ignoring case
  // container items need a container size since the end formula uses it
  // number items have no containers so their low-stock level must be exact
  '''
  CREATE TABLE stock_items (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT NOT NULL COLLATE NOCASE UNIQUE
                    CHECK (name = trim(name) AND name <> ''),
    category        TEXT NOT NULL,
    base_unit       TEXT NOT NULL CHECK (base_unit IN ('g', 'ml', 'pcs')),
    count_type      TEXT NOT NULL CHECK (count_type IN ('container', 'number')),
    container_label TEXT,
    container_size  REAL,
    low_mode        TEXT NOT NULL CHECK (low_mode IN ('containers', 'exact')),
    low_value       REAL NOT NULL DEFAULT 0 CHECK (low_value >= 0),
    sort_order      INTEGER NOT NULL DEFAULT 0,
    is_archived     INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
    -- "IS NOT NULL" is needed since NULL > 0 gives unknown, and sqlite lets unknown pass a CHECK
    CHECK (count_type = 'number'
        OR (container_size IS NOT NULL AND container_size > 0)),
    CHECK (count_type = 'container' OR low_mode = 'exact')
  )
  ''',

  // menu items, recipe lines and tally lines, see menuTableStatements below
  ...menuTableStatements,

  // one row per business day
  // covers_from is set when one count covers skipped open days
  // summary_source = which summary went into the report, ai or template
  '''
  CREATE TABLE business_days (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    business_date  TEXT NOT NULL UNIQUE,
    status         TEXT NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft', 'submitted', 'closed')),
    covers_from    TEXT,
    day_note       TEXT,
    submitted_at   TEXT,
    summary_source TEXT CHECK (summary_source IS NULL
                               OR summary_source IN ('ai', 'template'))
  )
  ''',

  // one logbook row per day per stock item (start / in / out / end)
  // sealed, level and exact_qty are only for container items, null for number items
  // level is the opened container level from 0 (none) to 1 (full)
  // the *_is_exact columns are 1 when there is no level guess in the count
  // touched = 1 once the barista changed this line in the draft
  '''
  CREATE TABLE count_lines (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    day_id         INTEGER NOT NULL REFERENCES business_days(id),
    stock_item_id  INTEGER NOT NULL REFERENCES stock_items(id),
    start_qty      REAL NOT NULL DEFAULT 0 CHECK (start_qty >= 0),
    start_is_exact INTEGER NOT NULL DEFAULT 1 CHECK (start_is_exact IN (0, 1)),
    in_qty         REAL NOT NULL DEFAULT 0 CHECK (in_qty >= 0),
    out_count      INTEGER NOT NULL DEFAULT 0 CHECK (out_count >= 0),
    sealed         INTEGER CHECK (sealed IS NULL OR sealed >= 0),
    level          REAL CHECK (level IS NULL OR (level >= 0 AND level <= 1)),
    exact_qty      REAL CHECK (exact_qty IS NULL OR exact_qty >= 0),
    end_qty        REAL NOT NULL DEFAULT 0 CHECK (end_qty >= 0),
    end_is_exact   INTEGER NOT NULL DEFAULT 1 CHECK (end_is_exact IN (0, 1)),
    touched        INTEGER NOT NULL DEFAULT 0 CHECK (touched IN (0, 1)),
    note           TEXT,
    UNIQUE (day_id, stock_item_id)
  )
  ''',

  // every IN (restock) and OUT (container finished) tap, with its time
  // qty = base units for in, 1 for out
  // prev_* = sealed/level/exact before an out tap, so undo puts them back exactly
  '''
  CREATE TABLE stock_events (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    day_id        INTEGER NOT NULL REFERENCES business_days(id),
    stock_item_id INTEGER NOT NULL REFERENCES stock_items(id),
    kind          TEXT NOT NULL CHECK (kind IN ('in', 'out')),
    qty           REAL NOT NULL CHECK (qty > 0),
    prev_sealed   INTEGER,
    prev_level    REAL,
    prev_exact    REAL,
    created_at    TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_stock_events_day ON stock_events (day_id, stock_item_id)',
  // for container checks, which look back at an item's past out events
  'CREATE INDEX idx_stock_events_item ON stock_events (stock_item_id, kind)',

  // computed numbers per day per item, saved at submit and redone on correction
  // gap only exists when the actual is exact and there is an expected number
  '''
  CREATE TABLE day_results (
    day_id          INTEGER NOT NULL REFERENCES business_days(id),
    stock_item_id   INTEGER NOT NULL REFERENCES stock_items(id),
    expected_qty    REAL,
    actual_qty      REAL NOT NULL,
    actual_is_exact INTEGER NOT NULL CHECK (actual_is_exact IN (0, 1)),
    gap             REAL,
    restock_flag    INTEGER NOT NULL DEFAULT 0 CHECK (restock_flag IN (0, 1)),
    PRIMARY KEY (day_id, stock_item_id),
    CHECK (gap IS NULL OR (actual_is_exact = 1 AND expected_qty IS NOT NULL))
  )
  ''',

  // containers finished vs what the recipes explain since the last finished one
  '''
  CREATE TABLE container_checks (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    day_id              INTEGER NOT NULL REFERENCES business_days(id),
    stock_item_id       INTEGER NOT NULL REFERENCES stock_items(id),
    containers          INTEGER NOT NULL CHECK (containers > 0),
    container_total     REAL NOT NULL,
    expected_since_last REAL,
    since_date          TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_container_checks_day ON container_checks (day_id)',

  // log of every correction, never overwrite silently
  // line_id points to a count_lines or tally_lines row depending on target, so no foreign key here
  // old/new value are text since the field can be a number or a note
  '''
  CREATE TABLE corrections (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    day_id       INTEGER NOT NULL REFERENCES business_days(id),
    target       TEXT NOT NULL CHECK (target IN ('count', 'tally')),
    line_id      INTEGER NOT NULL,
    field        TEXT NOT NULL,
    old_value    TEXT,
    new_value    TEXT,
    reason       TEXT NOT NULL CHECK (trim(reason) <> ''),
    corrected_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_corrections_day ON corrections (day_id)',

  // every email waits here first, then gets sent (or retried later if no internet)
  // recovery = pin recovery code email, has no day and its body gets blanked after sending
  '''
  CREATE TABLE outbox (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    kind       TEXT NOT NULL CHECK (kind IN ('daily', 'correction', 'recovery')),
    day_id     INTEGER REFERENCES business_days(id),
    subject    TEXT NOT NULL,
    html_body  TEXT NOT NULL,
    status     TEXT NOT NULL DEFAULT 'queued'
               CHECK (status IN ('queued', 'sent', 'failed')),
    attempts   INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TEXT NOT NULL,
    sent_at    TEXT
  )
  ''',
  // for finding emails that still need sending
  'CREATE INDEX idx_outbox_status ON outbox (status)',
];

// recipe_lines.input_unit = the unit the owner typed the amount in, like 'oz'
// only for showing "6 oz (177.44 ml)", the math always uses amount in the base unit
// null = typed in the base unit itself
// in one place since the new table and the version 3 upgrade both need the same rule
const String recipeInputUnitCheck =
    "CHECK (input_unit IS NULL OR input_unit IN ('g','kg','ml','L','oz','pcs'))";

// the menu, recipe and tally tables, kept in their own list so the version 2 upgrade
// can make them again (see DatabaseHelper.onUpgrade)
// there is no sizes table, every size is its own menu item like "Iced Americano (Large)" (rule 6)
const List<String> menuTableStatements = [
  // things on the menu, like "Iced Americano (Large)", "French Fries", "Espresso shot"
  // price_hint is only shown in the tally to help pick the right item, never added up
  // no_stock = 1 for items that use nothing the app counts, they never show "no recipe yet"
  // archived_at must be filled only when archived, restore uses it to find the recipe lines archived with it
  '''
  CREATE TABLE menu_items (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL COLLATE NOCASE UNIQUE
                CHECK (name = trim(name) AND name <> ''),
    category    TEXT NOT NULL,
    price_hint  REAL CHECK (price_hint IS NULL OR price_hint >= 0),
    no_stock    INTEGER NOT NULL DEFAULT 0 CHECK (no_stock IN (0, 1)),
    sort_order  INTEGER NOT NULL DEFAULT 0,
    is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
    archived_at TEXT,
    CHECK ((is_archived = 0 AND archived_at IS NULL)
        OR (is_archived = 1 AND archived_at IS NOT NULL))
  )
  ''',

  // recipe of one menu item = how much of each stock item it uses
  // editing an amount archives the old line and adds a new one, so old reports can still find the old amount
  // archived_at must be filled only when the line is archived
  '''
  CREATE TABLE recipe_lines (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    menu_item_id  INTEGER NOT NULL REFERENCES menu_items(id),
    stock_item_id INTEGER NOT NULL REFERENCES stock_items(id),
    amount        REAL NOT NULL CHECK (amount > 0),
    input_unit    TEXT $recipeInputUnitCheck,
    is_archived   INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
    created_at    TEXT NOT NULL,
    archived_at   TEXT,
    CHECK ((is_archived = 0 AND archived_at IS NULL)
        OR (is_archived = 1 AND archived_at IS NOT NULL))
  )
  ''',

  // only one ACTIVE line per menu item + stock item, archived lines dont count (partial unique index)
  '''
  CREATE UNIQUE INDEX idx_recipe_lines_active
    ON recipe_lines (menu_item_id, stock_item_id)
    WHERE is_archived = 0
  ''',

  // to quickly get all lines of a menu item, including archived ones when recalculating an old day
  'CREATE INDEX idx_recipe_lines_menu ON recipe_lines (menu_item_id)',

  // how many of each menu item were made that day, no prices
  '''
  CREATE TABLE tally_lines (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    day_id       INTEGER NOT NULL REFERENCES business_days(id),
    menu_item_id INTEGER NOT NULL REFERENCES menu_items(id),
    qty          INTEGER NOT NULL DEFAULT 0 CHECK (qty >= 0),
    UNIQUE (day_id, menu_item_id)
  )
  ''',
];
