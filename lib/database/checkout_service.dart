import 'package:sqflite/sqflite.dart';

import '../logic/fefo_engine.dart';
import '../logic/mutex.dart';
import '../models/order_line.dart';
import '../models/inventory_batch.dart' show formatDate;
import '../models/recipe_blueprint.dart';
import 'database_helper.dart';
import 'recipe_repository.dart';
import 'shift_repository.dart';

/// thrown inside the transaction when stock can't cover the order, rolls everything back
class InsufficientStockException implements Exception {
  InsufficientStockException(this.ingredientName, this.shortfall, this.unit);
  final String ingredientName;
  final double shortfall;
  final String unit;
}

/// what checkout gives back on success
class CheckoutResult {
  const CheckoutResult({
    required this.transactionId,
    required this.total,
    required this.itemCount,
  });

  final int transactionId;
  final double total;
  final int itemCount;
}

/// writes a sale, the one place that turns an order into database rows
class CheckoutService {
  CheckoutService({
    DatabaseHelper? helper,
    RecipeRepository? recipes,
    ShiftRepository? shifts,
  })  : _helper = helper ?? DatabaseHelper.instance,
        _recipes = recipes ?? RecipeRepository(),
        _shifts = shifts ?? ShiftRepository();

  final DatabaseHelper _helper;
  final RecipeRepository _recipes;
  final ShiftRepository _shifts;

  // one mutex for the whole app so two taps can't checkout at the same time
  static final Mutex _lock = Mutex();

  bool get isBusy => _lock.isBusy;

  /// records the sale and deducts ingredients, all or nothing
  Future<CheckoutResult> checkout(RunningOrder order, int userId) {
    // queued, so a second tap waits for the first sale to finish instead of racing it
    return _lock.run(() => _checkout(order, userId));
  }

  Future<CheckoutResult> _checkout(RunningOrder order, int userId) async {
    final db = await _helper.database;
    final shiftId = await _shifts.getOrCreateOpenShift(userId);
    final recipesByItem = await _recipes.getAllGroupedByMenuItem();
    // read once, so every batch in one sale is judged against the same date
    final today = DateTime.now();
    final now = today.toIso8601String();

    // everything below is one transaction, if any step throws nothing is written at all
    // without this a crash mid checkout could deduct stock for a sale that was never recorded
    return db.transaction((txn) async {
      final transactionId = await txn.insert('transactions', {
        'shift_id': shiftId,
        'transaction_datetime': now,
        'total_amount': order.total,
        'is_voided': 0,
        'voided_by': null,
      });

      for (final lineItem in order.lines) {
        await txn.insert('transaction_items', {
          'transaction_id': transactionId,
          'menu_item_id': lineItem.menuItem.menuItemId,
          'quantity': lineItem.quantity,
          // price snapshot (rule 8), editing the menu later must not rewrite this sale
          'unit_price_at_sale': lineItem.menuItem.sellingPrice,
          'line_total': lineItem.lineTotal,
        });
      }

      await _deductIngredients(txn, transactionId, order, recipesByItem, today);

      return CheckoutResult(
        transactionId: transactionId,
        total: order.total,
        itemCount: order.itemCount,
      );
    });
  }

  /// totals each ingredient across the whole order, then deducts it with fefo
  Future<void> _deductIngredients(
    DatabaseExecutor txn,
    int transactionId,
    RunningOrder order,
    Map<int, List<RecipeBlueprint>> recipesByItem,
    DateTime today,
  ) async {
    // 2 lattes needing 200ml each is one 400ml deduction, not two
    final needed = <int, double>{};
    final names = <int, RecipeBlueprint>{};

    for (final lineItem in order.lines) {
      final lines = recipesByItem[lineItem.menuItem.menuItemId] ?? const [];
      for (final r in lines) {
        needed[r.ingredientId] =
            (needed[r.ingredientId] ?? 0) + r.quantityRequired * lineItem.quantity;
        names[r.ingredientId] = r;
      }
    }

    for (final entry in needed.entries) {
      await _deductOneIngredient(
        txn,
        transactionId,
        entry.key,
        entry.value,
        names[entry.key]!,
        today,
      );
    }
  }

  Future<void> _deductOneIngredient(
    DatabaseExecutor txn,
    int transactionId,
    int ingredientId,
    double quantityNeeded,
    RecipeBlueprint info,
    DateTime today,
  ) async {
    // read batches inside the transaction, the screen's copy was loaded earlier and may be stale
    //
    // expired stock is excluded here as well as in the engine, because this is
    // the query a sale actually commits against and the rule has to hold even if
    // a caller somewhere passes the wrong date
    final rows = await txn.query(
      'inventory_batches',
      columns: ['batch_id', 'expiry_date', 'quantity_remaining'],
      where:
          'ingredient_id = ? AND quantity_remaining > 0 AND expiry_date >= ?',
      whereArgs: [ingredientId, formatDate(today)],
    );

    final batches = rows
        .map((r) => BatchStock(
              batchId: r['batch_id'] as int,
              expiryDate: r['expiry_date'] as String,
              quantityRemaining: (r['quantity_remaining'] as num).toDouble(),
            ))
        .toList();

    final plan = FefoEngine.plan(batches, quantityNeeded, today: today);

    // throwing rolls back the whole sale, the customer is told before anything is recorded
    if (!plan.isFullyCovered) {
      throw InsufficientStockException(
        info.ingredientName,
        plan.shortfall,
        info.unitOfMeasure,
      );
    }

    for (final deduction in plan.deductions) {
      // one row per batch touched (rule 3), this is what lets a void put each amount back exactly
      await txn.insert('batch_deductions', {
        'transaction_id': transactionId,
        'batch_id': deduction.batchId,
        'quantity_deducted': deduction.quantity,
      });

      // subtract in sql rather than writing a number we worked out earlier
      await txn.rawUpdate(
        'UPDATE inventory_batches SET quantity_remaining = quantity_remaining - ? '
        'WHERE batch_id = ?',
        [deduction.quantity, deduction.batchId],
      );
    }
  }
}
