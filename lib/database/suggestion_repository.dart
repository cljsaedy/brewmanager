import '../logic/suggestion_engine.dart';
import 'database_helper.dart';
import 'menu_item_repository.dart';
import 'recipe_repository.dart';

/// feeds the suggestion engine and records what it suggested
///
/// the logging is what makes the module evaluable, without it there is no way to
/// report whether the suggestions actually worked
class SuggestionRepository {
  SuggestionRepository({
    DatabaseHelper? helper,
    MenuItemRepository? menuItems,
    RecipeRepository? recipes,
  })  : _helper = helper ?? DatabaseHelper.instance,
        _menuItems = menuItems ?? MenuItemRepository(),
        _recipes = recipes ?? RecipeRepository();

  final DatabaseHelper _helper;
  final MenuItemRepository _menuItems;
  final RecipeRepository _recipes;

  /// the popularity window from the spec
  static const int popularityWindowDays = 7;

  /// builds the engine's inputs, menu items with their recipes and recent sales counts
  Future<List<SuggestionCandidate>> loadCandidates() async {
    final items = await _menuItems.getActive();
    final recipes = await _recipes.getAllGroupedByMenuItem();
    final sold = await timesSoldLast7Days();

    return items
        .map((item) => SuggestionCandidate(
              menuItem: item,
              recipeLines: recipes[item.menuItemId] ?? const [],
              timesSold: sold[item.menuItemId] ?? 0,
            ))
        .toList();
  }

  /// units sold per menu item over the trailing 7 days, voided sales excluded
  Future<Map<int, int>> timesSoldLast7Days() async {
    final db = await _helper.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: popularityWindowDays))
        .toIso8601String();

    final rows = await db.rawQuery('''
      SELECT ti.menu_item_id, SUM(ti.quantity) AS sold
      FROM transaction_items ti
      JOIN transactions t ON t.transaction_id = ti.transaction_id
      WHERE t.is_voided = 0 AND t.transaction_datetime >= ?
      GROUP BY ti.menu_item_id
    ''', [cutoff]);

    return {
      for (final row in rows)
        row['menu_item_id'] as int: (row['sold'] as num).toInt(),
    };
  }

  /// records a suggestion as shown, returns the row id so acceptance can be marked later
  ///
  /// batch_id is the batch that drove the expiry risk, so the log says which stock
  /// the suggestion was trying to save
  ///
  /// one row per shift per menu item, NOT one per time the banner appears
  /// the pos screen reloads constantly during a shift, and counting those as separate
  /// suggestions would make the acceptance rate depend on how often staff navigated
  /// rather than on whether the suggestion worked, which is the thing being measured
  Future<int?> logSuggestion({
    required int shiftId,
    required Suggestion suggestion,
  }) async {
    // the schema requires a batch, an item with nothing expiring has none to name
    if (suggestion.batchId == null) return null;

    final db = await _helper.database;
    final menuItemId = suggestion.menuItem.menuItemId;

    final existing = await db.query(
      'suggestion_logs',
      columns: ['suggestion_id'],
      where: 'shift_id = ? AND menu_item_id = ?',
      whereArgs: [shiftId, menuItemId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final id = existing.first['suggestion_id'] as int;

      // refresh the scores since risk climbs as the expiry gets closer,
      // was_accepted is left alone so an earlier acceptance isn't wiped out
      await db.update(
        'suggestion_logs',
        {
          'batch_id': suggestion.batchId,
          'expiry_risk_score': suggestion.expiryRiskScore,
          'popularity_score': suggestion.popularityScore,
          'combined_score': suggestion.combinedScore,
        },
        where: 'suggestion_id = ?',
        whereArgs: [id],
      );
      return id;
    }

    return db.insert('suggestion_logs', {
      'shift_id': shiftId,
      'menu_item_id': menuItemId,
      'batch_id': suggestion.batchId,
      'expiry_risk_score': suggestion.expiryRiskScore,
      'popularity_score': suggestion.popularityScore,
      'combined_score': suggestion.combinedScore,
      'was_accepted': 0,
      // the first time it was suggested this shift, not the last time it was shown
      'suggested_at': DateTime.now().toIso8601String(),
    });
  }

  /// flips was_accepted once the suggested item actually goes into an order
  Future<void> markAccepted(int suggestionId) async {
    final db = await _helper.database;
    await db.update(
      'suggestion_logs',
      {'was_accepted': 1},
      where: 'suggestion_id = ?',
      whereArgs: [suggestionId],
    );
  }

  /// how the suggestions have performed, for the evaluation chapter
  ///
  /// shown counts distinct suggestions (one per shift per item), so the rate reads
  /// "of the suggestions made, how many were acted on" rather than being diluted
  /// by how many times the banner happened to be on screen
  Future<({int shown, int accepted})> acceptanceStats() async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS shown,
             SUM(was_accepted) AS accepted
      FROM suggestion_logs
    ''');

    final row = rows.first;
    return (
      shown: (row['shown'] as num?)?.toInt() ?? 0,
      accepted: (row['accepted'] as num?)?.toInt() ?? 0,
    );
  }
}
