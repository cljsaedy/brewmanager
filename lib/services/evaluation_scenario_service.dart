import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../database/user_repository.dart';
import '../models/inventory_batch.dart';

/// thrown if this is somehow reached in a release build
class ScenarioNotAvailableException implements Exception {}

/// one specified batch in the scenario
class ScenarioBatch {
  final String ingredientName;
  final double containerCapacity;

  /// days from the load date, not a fixed calendar date
  ///
  /// absolute dates would drift into the past between runs and silently change the
  /// expiry colour bands, offsets keep the band behaviour identical every time
  final int expiresInDays;

  const ScenarioBatch({
    required this.ingredientName,
    required this.containerCapacity,
    required this.expiresInDays,
  });

  /// every batch starts full and as a single container
  double get quantity => containerCapacity;
}

/// resets the database to an exactly specified starting state
///
/// the accuracy tests need known starting quantities so the system's output can be
/// compared against values worked out by hand, and that only means anything if the
/// test can be re-run from the identical state
///
/// debug builds only, this wipes trading data and must never be reachable on the
/// tablet the cafe is actually using
class EvaluationScenarioService {
  EvaluationScenarioService({DatabaseHelper? helper})
      : _helper = helper ?? DatabaseHelper.instance;

  final DatabaseHelper _helper;

  // ---------------------------------------------------------------------------
  // the scenario, these are the numbers the printed test instrument refers to
  // ---------------------------------------------------------------------------

  /// name to unit, inserted in this order so ingredient_id is 1 to 4
  static const Map<String, String> ingredients = {
    'Fresh Milk': 'ml',
    'Espresso Beans': 'g',
    'Chocolate Syrup': 'ml',
    'Caramel Syrup': 'ml',
  };

  /// round prices so an order total can be checked in your head
  /// inserted in this order so menu_item_id is 1 to 5
  static const Map<String, double> menuItems = {
    'Espresso': 100.0,
    'Cappuccino': 140.0,
    'Latte': 150.0,
    'Mocha': 170.0,
    'Caramel Latte': 160.0,
  };

  /// menu item to its ingredients and how much of each per serving
  static const Map<String, Map<String, double>> recipes = {
    'Espresso': {'Espresso Beans': 18.0},
    'Cappuccino': {'Espresso Beans': 18.0, 'Fresh Milk': 150.0},
    'Latte': {'Espresso Beans': 18.0, 'Fresh Milk': 200.0},
    'Mocha': {
      'Espresso Beans': 18.0,
      'Fresh Milk': 200.0,
      'Chocolate Syrup': 30.0,
    },
    // caramel is stocked at exactly one serving, so the second one must be refused
    'Caramel Latte': {
      'Espresso Beans': 18.0,
      'Fresh Milk': 200.0,
      'Caramel Syrup': 50.0,
    },
  };

  /// inserted in this order so batch_id is 1 to 7
  ///
  /// milk is split four ways on purpose:
  ///  - batches 1 and 2 are small, so one latte (200ml) splits across two batches
  ///  - adding batch 3 lets three lattes (600ml) split across three batches
  ///  - batches 3 and 4 share an expiry with different quantities, which is the
  ///    rule 2 tie break, the smaller one must be depleted first
  static const List<ScenarioBatch> batches = [
    ScenarioBatch(
      ingredientName: 'Fresh Milk',
      containerCapacity: 150,
      expiresInDays: 2, // red band
    ),
    ScenarioBatch(
      ingredientName: 'Fresh Milk',
      containerCapacity: 200,
      expiresInDays: 4, // yellow band
    ),
    ScenarioBatch(
      ingredientName: 'Fresh Milk',
      containerCapacity: 500,
      expiresInDays: 10, // same expiry as the next one, smaller quantity
    ),
    ScenarioBatch(
      ingredientName: 'Fresh Milk',
      containerCapacity: 1000,
      expiresInDays: 10,
    ),
    ScenarioBatch(
      ingredientName: 'Espresso Beans',
      containerCapacity: 1000,
      expiresInDays: 30,
    ),
    ScenarioBatch(
      ingredientName: 'Chocolate Syrup',
      containerCapacity: 750,
      expiresInDays: 6, // yellow band
    ),
    ScenarioBatch(
      ingredientName: 'Caramel Syrup',
      containerCapacity: 50,
      expiresInDays: 8, // green band, and exactly one caramel latte's worth
    ),
  ];

  /// everything that gets emptied, children before parents because foreign keys are on
  ///
  /// users is deliberately absent here, wiping it would lock everyone out,
  /// [resetToFirstLaunch] handles users separately and re-seeds the manager
  static const List<String> _tablesToClear = [
    'suggestion_logs',
    'reconciliation_logs',
    'loss_events',
    'batch_deductions',
    'transaction_items',
    'transactions',
    'shift_sessions',
    'recipe_blueprints',
    'inventory_batches',
    'menu_items',
    'ingredients',
  ];

  /// total milk across all four batches, stated so the test instrument can cite it
  static double get totalMilk => batches
      .where((b) => b.ingredientName == 'Fresh Milk')
      .fold<double>(0, (sum, b) => sum + b.quantity);

  /// wipes trading data and writes the scenario, all in one transaction
  Future<void> load() async {
    if (!kDebugMode) throw ScenarioNotAvailableException();

    final db = await _helper.database;

    await db.transaction((txn) async {
      for (final table in _tablesToClear) {
        await txn.delete(table);
      }

      // restart the id counters so batch 1 is always the same batch every run,
      // which lets the printed test refer to batch numbers
      await _resetAutoIncrement(txn);

      final ingredientIds = await _insertIngredients(txn);
      final menuItemIds = await _insertMenuItems(txn);
      await _insertRecipes(txn, menuItemIds, ingredientIds);
      await _insertBatches(txn, ingredientIds);
    });
  }

  /// empties everything and puts the database back to how a fresh install looks
  ///
  /// for checking the first launch experience without uninstalling, so staff,
  /// the seeded sample data and all trading history go, and the default manager
  /// is written back so the app is still reachable
  ///
  /// the dev sample data is deliberately NOT re-seeded, the point is an empty app
  Future<void> resetToFirstLaunch() async {
    if (!kDebugMode) throw ScenarioNotAvailableException();

    final db = await _helper.database;

    await db.transaction((txn) async {
      for (final table in _tablesToClear) {
        await txn.delete(table);
      }
      // users goes too, which is the difference from loading the scenario
      await txn.delete('users');

      await _resetAutoIncrement(txn);
      await txn.execute("DELETE FROM sqlite_sequence WHERE name = 'users'");

      // without this there is no way back into the app at all
      await UserRepository.seedDefaultManager(txn);
    });
  }

  Future<void> _resetAutoIncrement(DatabaseExecutor txn) async {
    // sqlite keeps the counters in its own table, clearing a row restarts that table at 1
    final names = _tablesToClear.map((t) => "'$t'").join(', ');
    try {
      await txn.execute('DELETE FROM sqlite_sequence WHERE name IN ($names)');
    } catch (_) {
      // the table only exists once an AUTOINCREMENT table has been written to,
      // so a database that has never been used has nothing to reset
    }
  }

  Future<Map<String, int>> _insertIngredients(DatabaseExecutor txn) async {
    final ids = <String, int>{};
    for (final entry in ingredients.entries) {
      ids[entry.key] = await txn.insert('ingredients', {
        'name': entry.key,
        'unit_of_measure': entry.value,
        'is_archived': 0,
      });
    }
    return ids;
  }

  Future<Map<String, int>> _insertMenuItems(DatabaseExecutor txn) async {
    final ids = <String, int>{};
    for (final entry in menuItems.entries) {
      ids[entry.key] = await txn.insert('menu_items', {
        'name': entry.key,
        'selling_price': entry.value,
        'is_archived': 0,
      });
    }
    return ids;
  }

  Future<void> _insertRecipes(
    DatabaseExecutor txn,
    Map<String, int> menuItemIds,
    Map<String, int> ingredientIds,
  ) async {
    for (final recipe in recipes.entries) {
      for (final line in recipe.value.entries) {
        await txn.insert('recipe_blueprints', {
          'menu_item_id': menuItemIds[recipe.key],
          'ingredient_id': ingredientIds[line.key],
          'quantity_required': line.value,
        });
      }
    }
  }

  Future<void> _insertBatches(
    DatabaseExecutor txn,
    Map<String, int> ingredientIds,
  ) async {
    final now = DateTime.now();
    final receivedAt = now.toIso8601String();

    for (final batch in batches) {
      await txn.insert('inventory_batches', {
        'ingredient_id': ingredientIds[batch.ingredientName],
        'expiry_date': formatDate(
          now.add(Duration(days: batch.expiresInDays)),
        ),
        'container_capacity': batch.containerCapacity,
        // one container each, so a sealed count of 2 is an impossible count
        'containers_received': 1,
        'quantity_remaining': batch.quantity,
        'received_at': receivedAt,
      });
    }
  }
}
