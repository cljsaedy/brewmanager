import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/inventory_batch.dart';
import '../security/pin_hasher.dart';

/// sample data for testing, only runs in debug builds (see kDebugMode check in DatabaseHelper)
///
/// this is meant to look like a small cafe part way through a normal week, partly
/// used stock, an uneven week of sales, a couple of recorded accidents
///
/// deliberately NOT exact, the evaluation scenario loader is the one that sets
/// known round quantities for hand-checked accuracy tests, this one is for judging
/// whether the screens hold up against realistic data
class DevSeed {
  DevSeed._();

  /// pins for the seeded baristas, the manager still starts on 0000
  static const String baristaPin = '1111';
  static const String secondBaristaPin = '2222';

  /// set to false to get a database with no trading history
  ///
  /// the history makes the loss chart and the exports worth looking at, but it
  /// also means there are always sales in the last 7 days, so the suggestion
  /// engine's cold start path can't be reached, flip this off to demo that
  static const bool seedHistory = true;

  static Future<void> run(DatabaseExecutor txn) async {
    final baristaIds = await _seedBaristas(txn);
    final ingredientIds = await _seedIngredients(txn);
    final menuItemIds = await _seedMenuItems(txn);
    await _seedRecipes(txn, menuItemIds, ingredientIds);
    await _seedCurrentBatches(txn, ingredientIds);

    if (seedHistory) {
      await _DevHistory(
        txn: txn,
        baristaIds: baristaIds,
        ingredientIds: ingredientIds,
        menuItemIds: menuItemIds,
      ).seed();
    }
  }

  static Future<List<int>> _seedBaristas(DatabaseExecutor txn) async {
    final ids = <int>[];
    for (final (name, pin) in [
      ('Ana', baristaPin),
      ('Miguel', secondBaristaPin),
    ]) {
      ids.add(await txn.insert('users', {
        'name': name,
        'role': UserRole.barista.dbValue,
        'pin_hash': PinHasher.hash(pin),
        'is_active': 1,
      }));
    }
    return ids;
  }

  /// what a small cafe actually keeps behind the counter
  static Future<Map<String, int>> _seedIngredients(
    DatabaseExecutor txn,
  ) async {
    const items = {
      'Fresh Milk': 'ml',
      'Espresso Beans': 'g',
      'Chocolate Syrup': 'ml',
      'Caramel Syrup': 'ml',
      'Vanilla Syrup': 'ml',
      'Whipped Cream': 'ml',
      'Cocoa Powder': 'g',
    };

    final ids = <String, int>{};
    for (final entry in items.entries) {
      ids[entry.key] = await txn.insert('ingredients', {
        'name': entry.key,
        'unit_of_measure': entry.value,
        'is_archived': 0,
      });
    }
    return ids;
  }

  /// hot and iced are separate menu items, drink size variants are out of scope
  /// so each one is its own item rather than an option on one
  static const Map<String, double> _menu = {
    'Espresso': 95,
    'Americano': 105,
    'Iced Americano': 115,
    'Cappuccino': 125,
    'Latte': 135,
    'Iced Latte': 145,
    'Vanilla Latte': 150,
    'Mocha': 160,
    'Iced Mocha': 170,
    'Caramel Macchiato': 165,
    'Hot Chocolate': 120,
    'Caramel Frappe': 175,
    // pastries, bought in and sold as they come
    'Butter Croissant': 90,
    'Banana Bread': 85,
  };

  /// sold as whole units, so no recipe, no stock movement and no closing count
  ///
  /// the study's scope allows prepared food on the till without tracking it at
  /// ingredient level, these are here so that path can actually be tested
  static const Set<String> _wholeUnitItems = {
    'Butter Croissant',
    'Banana Bread',
  };

  static Future<Map<String, int>> _seedMenuItems(DatabaseExecutor txn) async {
    final ids = <String, int>{};
    for (final entry in _menu.entries) {
      ids[entry.key] = await txn.insert('menu_items', {
        'name': entry.key,
        'selling_price': entry.value,
        'is_archived': 0,
        'is_ingredient_tracked': _wholeUnitItems.contains(entry.key) ? 0 : 1,
      });
    }
    return ids;
  }

  /// most drinks share milk and beans on purpose, so the pos grayout from a
  /// shared ingredient running low shows up straight away
  static Future<void> _seedRecipes(
    DatabaseExecutor txn,
    Map<String, int> menuItems,
    Map<String, int> ingredients,
  ) async {
    const recipes = {
      'Espresso': {'Espresso Beans': 18.0},
      'Americano': {'Espresso Beans': 18.0},
      'Iced Americano': {'Espresso Beans': 18.0},
      'Cappuccino': {'Espresso Beans': 18.0, 'Fresh Milk': 150.0},
      'Latte': {'Espresso Beans': 18.0, 'Fresh Milk': 200.0},
      'Iced Latte': {'Espresso Beans': 18.0, 'Fresh Milk': 200.0},
      'Vanilla Latte': {
        'Espresso Beans': 18.0,
        'Fresh Milk': 200.0,
        'Vanilla Syrup': 30.0,
      },
      'Mocha': {
        'Espresso Beans': 18.0,
        'Fresh Milk': 200.0,
        'Chocolate Syrup': 30.0,
      },
      'Iced Mocha': {
        'Espresso Beans': 18.0,
        'Fresh Milk': 200.0,
        'Chocolate Syrup': 30.0,
      },
      'Caramel Macchiato': {
        'Espresso Beans': 18.0,
        'Fresh Milk': 200.0,
        'Caramel Syrup': 30.0,
      },
      'Hot Chocolate': {'Fresh Milk': 250.0, 'Cocoa Powder': 20.0},
      'Caramel Frappe': {
        'Espresso Beans': 18.0,
        'Fresh Milk': 200.0,
        'Caramel Syrup': 30.0,
        'Whipped Cream': 30.0,
      },
    };

    for (final recipe in recipes.entries) {
      for (final line in recipe.value.entries) {
        await txn.insert('recipe_blueprints', {
          'menu_item_id': menuItems[recipe.key],
          'ingredient_id': ingredients[line.key],
          'quantity_required': line.value,
        });
      }
    }
  }

  /// stock as it would look mid week, partly used and expiring at different times
  ///
  /// milk goes off in days, syrups last months, which is what makes the expiry
  /// matrix worth looking at
  static Future<void> _seedCurrentBatches(
    DatabaseExecutor txn,
    Map<String, int> ingredients,
  ) async {
    final now = DateTime.now();

    // ingredient, days to expiry, container size, containers, how much is left
    final batches = [
      // older milk that needs using first, one carton part used
      ('Fresh Milk', 2, 1000.0, 2, 1400.0),
      // this week's delivery
      ('Fresh Milk', 6, 1000.0, 6, 6000.0),
      ('Espresso Beans', 60, 1000.0, 2, 1350.0),
      ('Chocolate Syrup', 95, 750.0, 1, 480.0),
      ('Caramel Syrup', 110, 750.0, 1, 625.0),
      ('Vanilla Syrup', 88, 750.0, 1, 300.0),
      // cream is the other short dated item
      ('Whipped Cream', 9, 500.0, 2, 850.0),
      ('Cocoa Powder', 240, 500.0, 1, 410.0),
      // a carton that went off before anyone used it, still physically on the
      // shelf and still counted at the audit, but the till must refuse to sell
      // it, which is only testable if some expired stock exists
      ('Vanilla Syrup', -3, 750.0, 1, 500.0),
    ];

    for (final (name, days, capacity, count, remaining) in batches) {
      await txn.insert('inventory_batches', {
        'ingredient_id': ingredients[name],
        'expiry_date': formatDate(now.add(Duration(days: days))),
        'container_capacity': capacity,
        'containers_received': count,
        'quantity_remaining': remaining,
        'received_at': now
            .subtract(Duration(days: days > 30 ? 20 : 3))
            .toIso8601String(),
      });
    }
  }
}

/// a week of past trading, so the loss chart, the reports and the exports have
/// something in them
///
/// it all hangs off separate historical batches that are already used up, the
/// current stock above is left alone
///
/// every shift it creates is CLOSED, the app should never start with a shift open
/// that nobody opened
class _DevHistory {
  _DevHistory({
    required this.txn,
    required this.baristaIds,
    required this.ingredientIds,
    required this.menuItemIds,
  });

  final DatabaseExecutor txn;
  final List<int> baristaIds;
  final Map<String, int> ingredientIds;
  final Map<String, int> menuItemIds;

  final DateTime _now = DateTime.now();

  /// fixed seed, so two installs produce the same week and a bug is reproducible
  final Random _random = Random(20261013);

  /// used up historical batches, by key
  final Map<String, int> _oldBatches = {};

  /// shift_id per day, oldest first
  final List<int> _shifts = [];

  /// how many days of history to write
  static const int _days = 7;

  Future<void> seed() async {
    await _seedOldBatches();
    await _seedClosedShifts();
    await _seedSales();
    await _seedDeclaredLosses();
    await _seedReconciliations();
  }

  DateTime _daysAgo(int days) => _now.subtract(Duration(days: days));

  /// last week's stock, now expired and at zero
  Future<void> _seedOldBatches() async {
    // key, ingredient, container size, containers received
    final old = [
      ('milk_a', 'Fresh Milk', 1000.0, 8),
      ('milk_b', 'Fresh Milk', 1000.0, 6),
      ('beans', 'Espresso Beans', 1000.0, 2),
      ('choc', 'Chocolate Syrup', 750.0, 2),
      ('cream', 'Whipped Cream', 500.0, 3),
    ];

    for (final (key, name, capacity, count) in old) {
      _oldBatches[key] = await txn.insert('inventory_batches', {
        'ingredient_id': ingredientIds[name],
        // expired, so it never shows as usable stock
        'expiry_date': formatDate(_daysAgo(2 + old.length)),
        'container_capacity': capacity,
        'containers_received': count,
        'quantity_remaining': 0,
        'received_at': _daysAgo(20).toIso8601String(),
      });
    }
  }

  /// one closed shift per day, alternating between the two baristas
  Future<void> _seedClosedShifts() async {
    for (var day = _days; day >= 1; day--) {
      final date = _daysAgo(day);
      // a real trading day, open at 7am and close at 7pm
      final opened = DateTime(date.year, date.month, date.day, 7);
      final closed = opened.add(const Duration(hours: 12));

      _shifts.add(await txn.insert('shift_sessions', {
        'user_id': baristaIds[day % baristaIds.length],
        'opened_at': opened.toIso8601String(),
        'closed_at': closed.toIso8601String(),
        'status': 'closed',
      }));
    }
  }

  /// how often each drink sells, iced drinks lead because the cafe is in quezon city
  ///
  /// the weights make one item clearly the most popular, which is what the
  /// suggestion engine's popularity term needs to rank against
  static const Map<String, int> _popularity = {
    'Iced Latte': 22,
    'Iced Americano': 16,
    'Latte': 14,
    'Cappuccino': 11,
    'Iced Mocha': 9,
    'Caramel Macchiato': 8,
    'Americano': 7,
    'Espresso': 6,
    'Vanilla Latte': 5,
    'Mocha': 5,
    'Caramel Frappe': 4,
    'Hot Chocolate': 3,
    // pastries sell steadily, which is also what makes them a good test that a
    // popular item with no stock behind it never gets suggested
    'Butter Croissant': 12,
    'Banana Bread': 7,
  };

  /// a week of orders, busier at weekends, each order one to three drinks
  Future<void> _seedSales() async {
    final weighted = <String>[
      for (final entry in _popularity.entries)
        for (var i = 0; i < entry.value; i++) entry.key,
    ];

    for (var index = 0; index < _shifts.length; index++) {
      final daysAgo = _days - index;
      final date = _daysAgo(daysAgo);
      // saturday and sunday are busier
      final isWeekend = date.weekday >= 6;
      final orderCount = (isWeekend ? 14 : 9) + _random.nextInt(4);

      for (var order = 0; order < orderCount; order++) {
        // spread across the trading day, roughly 8am to 6pm
        final at = DateTime(date.year, date.month, date.day, 8)
            .add(Duration(minutes: _random.nextInt(600)));

        final lineCount = 1 + _random.nextInt(3);
        final lines = <String, int>{};
        for (var line = 0; line < lineCount; line++) {
          final item = weighted[_random.nextInt(weighted.length)];
          lines[item] = (lines[item] ?? 0) + 1;
        }

        await _writeSale(
          shiftId: _shifts[index],
          at: at,
          lines: lines,
          // roughly one order in twenty five was rung up wrong and voided
          isVoided: _random.nextInt(25) == 0,
        );
      }
    }
  }

  Future<void> _writeSale({
    required int shiftId,
    required DateTime at,
    required Map<String, int> lines,
    required bool isVoided,
  }) async {
    final total = lines.entries.fold<double>(
      0,
      (sum, e) => sum + DevSeed._menu[e.key]! * e.value,
    );

    final transactionId = await txn.insert('transactions', {
      'shift_id': shiftId,
      'transaction_datetime': at.toIso8601String(),
      'total_amount': total,
      'is_voided': isVoided ? 1 : 0,
      'voided_by': null,
    });

    for (final entry in lines.entries) {
      final price = DevSeed._menu[entry.key]!;
      await txn.insert('transaction_items', {
        'transaction_id': transactionId,
        'menu_item_id': menuItemIds[entry.key],
        'quantity': entry.value,
        // the price snapshot, same as a real sale would record
        'unit_price_at_sale': price,
        'line_total': price * entry.value,
      });
    }

    // one deduction against last week's milk, so voiding a seeded sale has
    // something to put back rather than nothing at all
    await txn.insert('batch_deductions', {
      'transaction_id': transactionId,
      'batch_id': _oldBatches['milk_a'],
      'quantity_deducted': 150.0 * lines.values.fold<int>(0, (a, b) => a + b),
    });
  }

  /// the accidents a cafe actually has, a dropped carton and a split cream
  Future<void> _seedDeclaredLosses() async {
    // shift index, batch key, containers lost, container size
    final losses = [
      (1, 'milk_a', 1, 1000.0),
      (3, 'cream', 1, 500.0),
      (5, 'choc', 1, 750.0),
    ];

    for (final (shiftIndex, key, containers, capacity) in losses) {
      await txn.insert('loss_events', {
        'shift_id': _shifts[shiftIndex],
        'batch_id': _oldBatches[key],
        'containers_lost': containers,
        'quantity_deducted': containers * capacity,
        'recorded_at': _daysAgo(_days - shiftIndex)
            .add(const Duration(hours: 11))
            .toIso8601String(),
      });
    }
  }

  /// closing counts covering every variance case the reconciliation module reports
  Future<void> _seedReconciliations() async {
    // shift index, batch key, theoretical, audited, type
    final logs = [
      // ordinary drift, a bit of milk short most days
      (0, 'milk_a', 4200.0, 4050.0, 'unexplained'),
      (1, 'milk_a', 3100.0, 2900.0, 'unexplained'),
      (2, 'beans', 1600.0, 1520.0, 'unexplained'),
      (3, 'milk_b', 5000.0, 4800.0, 'unexplained'),
      (4, 'choc', 900.0, 810.0, 'unexplained'),
      // a count that came out over, which must not show up as a loss
      (4, 'cream', 700.0, 780.0, 'unexplained'),
      // the rotation break pair, two milk batches cancelling out
      (5, 'milk_a', 2000.0, 2500.0, 'unexplained'),
      (5, 'milk_b', 3000.0, 2500.0, 'unexplained'),
      // stock that arrived without being recorded
      (6, 'beans', 1000.0, 2000.0, 'unrecorded_receiving'),
    ];

    for (final (shiftIndex, key, theoretical, audited, type) in logs) {
      await txn.insert('reconciliation_logs', {
        'shift_id': _shifts[shiftIndex],
        'batch_id': _oldBatches[key],
        'theoretical_quantity': theoretical,
        'audited_quantity': audited,
        'variance': audited - theoretical,
        'variance_type': type,
      });
    }
  }
}
