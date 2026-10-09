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

  static Future<void> run(DatabaseExecutor txn) async {
    await _seedBarista(txn);
    final ingredientIds = await _seedIngredients(txn);
    final menuItemIds = await _seedMenuItems(txn);
    await _seedRecipes(txn, menuItemIds, ingredientIds);
    await _seedBatches(txn, ingredientIds);
  }

  static Future<void> _seedBarista(DatabaseExecutor txn) async {
    await txn.insert('users', {
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
