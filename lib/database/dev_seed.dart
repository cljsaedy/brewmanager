import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import '../models/inventory_batch.dart';
import '../security/pin_hasher.dart';

/// sample data for testing, only runs in debug builds (see kDebugMode check in DatabaseHelper)
/// a release build for the cafe gets an empty database, this is a development fixture not part of the system
class DevSeed {
  DevSeed._();

  /// barista pin for testing role routing, the manager still starts on 0000 and must change it
  static const String baristaPin = '1111';

  /// set to false to get a database with no trading history
  ///
  /// the history makes the loss chart and the exports worth looking at, but it also
  /// means there are always sales in the last 7 days, so the suggestion engine's
  /// cold start path can't be reached, flip this off to demo that
  static const bool seedHistory = true;

  static Future<void> run(DatabaseExecutor txn) async {
    final baristaId = await _seedBarista(txn);
    final ingredientIds = await _seedIngredients(txn);
    final menuItemIds = await _seedMenuItems(txn);
    await _seedRecipes(txn, menuItemIds, ingredientIds);
    await _seedBatches(txn, ingredientIds);

    if (seedHistory) {
      await _DevHistory(
        txn: txn,
        baristaId: baristaId,
        ingredientIds: ingredientIds,
        menuItemIds: menuItemIds,
      ).seed();
    }
  }

  static Future<int> _seedBarista(DatabaseExecutor txn) async {
    return txn.insert('users', {
      'name': 'Test Barista',
      'role': UserRole.barista.dbValue,
      'pin_hash': PinHasher.hash(baristaPin),
      'is_active': 1,
    });
  }

  /// returns name → ingredient_id so the recipes below can refer to them
  static Future<Map<String, int>> _seedIngredients(DatabaseExecutor txn) async {
    const items = {
      'Fresh Milk': 'ml',
      'Espresso Beans': 'g',
      'Chocolate Syrup': 'ml',
      'Caramel Syrup': 'ml',
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

  static Future<Map<String, int>> _seedMenuItems(DatabaseExecutor txn) async {
    const items = {
      'Espresso': 95.0,
      'Americano': 100.0,
      'Cappuccino': 115.0,
      'Latte': 120.0,
      'Mocha': 135.0,
    };

    final ids = <String, int>{};
    for (final entry in items.entries) {
      ids[entry.key] = await txn.insert('menu_items', {
        'name': entry.key,
        'selling_price': entry.value,
        'is_archived': 0,
      });
    }
    return ids;
  }

  /// latte, cappuccino and mocha all use milk on purpose, so the pos grayout from a shared ingredient shows up straight away
  static Future<void> _seedRecipes(
    DatabaseExecutor txn,
    Map<String, int> menuItems,
    Map<String, int> ingredients,
  ) async {
    const recipes = {
      'Espresso': {'Espresso Beans': 18.0},
      'Americano': {'Espresso Beans': 18.0},
      'Cappuccino': {'Espresso Beans': 18.0, 'Fresh Milk': 150.0},
      'Latte': {'Espresso Beans': 18.0, 'Fresh Milk': 200.0},
      'Mocha': {
        'Espresso Beans': 18.0,
        'Fresh Milk': 200.0,
        'Chocolate Syrup': 30.0,
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

  /// expiry dates are relative to today so the colour bands stay meaningful whenever you install
  static Future<void> _seedBatches(
    DatabaseExecutor txn,
    Map<String, int> ingredients,
  ) async {
    final now = DateTime.now();
    final receivedAt = now.toIso8601String();

    // ingredient, days until expiry, container size, how many containers
    final batches = [
      // two milk batches so a 200ml latte splits across both (150 then 50)
      ('Fresh Milk', 2, 150.0, 1),
      ('Fresh Milk', 10, 1000.0, 1),
      ('Chocolate Syrup', 5, 750.0, 1),
      ('Espresso Beans', 30, 1000.0, 1),
    ];

    for (final (name, days, capacity, count) in batches) {
      await txn.insert('inventory_batches', {
        'ingredient_id': ingredients[name],
        'expiry_date': formatDate(now.add(Duration(days: days))),
        'container_capacity': capacity,
        'containers_received': count,
        'quantity_remaining': capacity * count,
        'received_at': receivedAt,
      });
    }
  }
}

/// past trading, so the loss chart and the exports have something in them
///
/// all of it hangs off separate historical batches that are already used up and
/// expired, the current batches are left untouched so the pos, fefo and audit
/// screens still behave like a clean install
class _DevHistory {
  _DevHistory({
    required this.txn,
    required this.baristaId,
    required this.ingredientIds,
    required this.menuItemIds,
  });

  final DatabaseExecutor txn;
  final int baristaId;
  final Map<String, int> ingredientIds;
  final Map<String, int> menuItemIds;

  final DateTime _now = DateTime.now();

  /// batch_id of each used up historical batch, by ingredient name
  final Map<String, int> _oldBatches = {};

  /// shift_id of each closed shift, oldest first
  final List<int> _shifts = [];

  Future<void> seed() async {
    await _seedOldBatches();
    await _seedClosedShifts();
    await _seedSales();
    await _seedDeclaredLosses();
    await _seedReconciliations();
  }

  DateTime _daysAgo(int days) => _now.subtract(Duration(days: days));

  /// stock received three weeks ago, now expired and at zero
  Future<void> _seedOldBatches() async {
    // ingredient, container size, containers received
    final old = [
      ('Fresh Milk', 1000.0, 6),
      ('Espresso Beans', 1000.0, 2),
      ('Chocolate Syrup', 750.0, 2),
      // a second milk batch with the same size, for the rotation break pair
      ('Fresh Milk', 1000.0, 4),
    ];

    var index = 0;
    for (final (name, capacity, count) in old) {
      final id = await txn.insert('inventory_batches', {
        'ingredient_id': ingredientIds[name],
        // expired, so these never show up in the live expiry matrix as usable stock
        'expiry_date': formatDate(_daysAgo(8 + index)),
        'container_capacity': capacity,
        'containers_received': count,
        // used up, so they don't interfere with fefo or the pos grid
        'quantity_remaining': 0,
        'received_at': _daysAgo(21).toIso8601String(),
      });
      // the second milk batch is kept under its own key
      _oldBatches[index == 3 ? 'Fresh Milk 2' : name] = id;
      index++;
    }
  }

  /// three closed shifts, the losses and counts below belong to these
  Future<void> _seedClosedShifts() async {
    for (final daysAgo in [10, 5, 2]) {
      final opened = _daysAgo(daysAgo);
      final id = await txn.insert('shift_sessions', {
        'user_id': baristaId,
        'opened_at': opened.toIso8601String(),
        'closed_at': opened.add(const Duration(hours: 8)).toIso8601String(),
        'status': 'closed',
      });
      _shifts.add(id);
    }
  }

  /// sales across the last six days, so popularity has something to rank by
  ///
  /// latte is busiest, then cappuccino, so the suggestion engine's popularity
  /// term has a clear yardstick instead of everything tying
  Future<void> _seedSales() async {
    // days ago, menu item, how many
    final sales = [
      (6, 'Latte', 4),
      (6, 'Americano', 2),
      (5, 'Latte', 5),
      (5, 'Cappuccino', 3),
      (4, 'Latte', 3),
      (4, 'Mocha', 1),
      (3, 'Cappuccino', 4),
      (3, 'Espresso', 2),
      (2, 'Latte', 6),
      (2, 'Cappuccino', 2),
      (1, 'Latte', 4),
      (1, 'Mocha', 2),
    ];

    const prices = {
      'Espresso': 95.0,
      'Americano': 100.0,
      'Cappuccino': 115.0,
      'Latte': 120.0,
      'Mocha': 135.0,
    };

    for (final (daysAgo, itemName, quantity) in sales) {
      final price = prices[itemName]!;
      final lineTotal = price * quantity;
      // sales land in the shift that was open nearest that day
      final shiftId = _shifts[daysAgo >= 5 ? 0 : (daysAgo >= 2 ? 1 : 2)];

      final transactionId = await txn.insert('transactions', {
        'shift_id': shiftId,
        'transaction_datetime':
            _daysAgo(daysAgo).add(const Duration(hours: 3)).toIso8601String(),
        'total_amount': lineTotal,
        'is_voided': 0,
        'voided_by': null,
      });

      await txn.insert('transaction_items', {
        'transaction_id': transactionId,
        'menu_item_id': menuItemIds[itemName],
        'quantity': quantity,
        // the price snapshot, same as a real sale would record
        'unit_price_at_sale': price,
        'line_total': lineTotal,
      });

      // a deduction row against the old milk batch, so voiding a seeded sale
      // puts stock back somewhere sensible instead of having nothing to reverse
      await txn.insert('batch_deductions', {
        'transaction_id': transactionId,
        'batch_id': _oldBatches['Fresh Milk'],
        'quantity_deducted': 150.0 * quantity,
      });
    }
  }

  /// dropped containers, the known incident side of the loss chart
  Future<void> _seedDeclaredLosses() async {
    // shift index, batch key, containers lost, container size
    final losses = [
      (0, 'Fresh Milk', 1, 1000.0),
      (2, 'Chocolate Syrup', 1, 750.0),
    ];

    for (final (shiftIndex, batchKey, containers, capacity) in losses) {
      await txn.insert('loss_events', {
        'shift_id': _shifts[shiftIndex],
        'batch_id': _oldBatches[batchKey],
        'containers_lost': containers,
        'quantity_deducted': containers * capacity,
        'recorded_at': _daysAgo(shiftIndex == 0 ? 10 : 2)
            .add(const Duration(hours: 5))
            .toIso8601String(),
      });
    }
  }

  /// closing counts covering every variance case the reconciliation module reports
  Future<void> _seedReconciliations() async {
    // shift index, batch key, theoretical, audited, type
    final logs = [
      // plain unexplained shortfalls, the mystery drift the study is about
      (0, 'Espresso Beans', 2000.0, 1750.0, 'unexplained'),
      (1, 'Espresso Beans', 1750.0, 1600.0, 'unexplained'),
      (2, 'Chocolate Syrup', 1500.0, 1200.0, 'unexplained'),

      // a surplus, which must NOT appear as a loss on the chart
      (1, 'Chocolate Syrup', 1200.0, 1350.0, 'unexplained'),

      // a rotation break pair on the same ingredient, roughly cancelling out
      (2, 'Fresh Milk', 1500.0, 2000.0, 'unexplained'),
      (2, 'Fresh Milk 2', 2000.0, 1500.0, 'unexplained'),

      // stock that arrived without being recorded, kept out of loss totals
      (1, 'Fresh Milk 2', 3000.0, 4000.0, 'unrecorded_receiving'),
    ];

    for (final (shiftIndex, batchKey, theoretical, audited, type) in logs) {
      await txn.insert('reconciliation_logs', {
        'shift_id': _shifts[shiftIndex],
        'batch_id': _oldBatches[batchKey],
        'theoretical_quantity': theoretical,
        'audited_quantity': audited,
        'variance': audited - theoretical,
        'variance_type': type,
      });
    }
  }
}
