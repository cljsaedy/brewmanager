/// groups loss records for the chart and the summary table
///
/// pure dart so it can be unit tested, the repository fetches the records
library;

import '../models/loss_record.dart';

/// one bar on the chart, split into its two category segments
class LossBar {
  /// what the bar is labelled with, an ingredient name or a date
  final String label;

  /// sort key, used to keep bars in a sensible order
  final String sortKey;

  final double declared;
  final double unexplained;

  /// the unit the numbers are in, 'containers' when ingredients are mixed
  final String unit;

  const LossBar({
    required this.label,
    required this.sortKey,
    required this.declared,
    required this.unexplained,
    required this.unit,
  });

  double get total => declared + unexplained;
}

/// one row of the summary table, exact figures in the ingredient's real unit
class LossSummaryRow {
  final String ingredientName;
  final String unitOfMeasure;
  final double declared;
  final double unexplained;

  const LossSummaryRow({
    required this.ingredientName,
    required this.unitOfMeasure,
    required this.declared,
    required this.unexplained,
  });

  double get total => declared + unexplained;
}

class LossAggregator {
  LossAggregator._();

  /// label used on the y axis when several ingredients with different units are mixed
  static const String mixedUnit = 'containers';

  /// true when the records span more than one unit, so quantities can't be added up
  static bool hasMixedUnits(List<LossRecord> records) {
    if (records.isEmpty) return false;
    final units = records.map((r) => r.unitOfMeasure).toSet();
    return units.length > 1;
  }

  /// one bar per ingredient, for when the chart covers everything
  ///
  /// uses containers when the units differ, because 500 ml of milk and 500 g of beans
  /// are not comparable amounts and stacking them on one axis would be misleading
  static List<LossBar> byIngredient(List<LossRecord> records) {
    final mixed = hasMixedUnits(records);

    final declared = <String, double>{};
    final unexplained = <String, double>{};
    final units = <String, String>{};

    for (final r in records) {
      final amount = mixed ? r.containersEquivalent : r.quantity;
      units[r.ingredientName] = mixed ? mixedUnit : r.unitOfMeasure;

      if (r.category == LossCategory.declared) {
        declared[r.ingredientName] = (declared[r.ingredientName] ?? 0) + amount;
      } else {
        unexplained[r.ingredientName] =
            (unexplained[r.ingredientName] ?? 0) + amount;
      }
    }

    final names = {...declared.keys, ...unexplained.keys}.toList();

    final bars = names
        .map((name) => LossBar(
              label: name,
              sortKey: name,
              declared: declared[name] ?? 0,
              unexplained: unexplained[name] ?? 0,
              unit: units[name] ?? mixedUnit,
            ))
        .toList();

    // biggest loss first, that's what the manager wants to see
    bars.sort((a, b) => b.total.compareTo(a.total));
    return bars;
  }

  /// one bar per day, for when a single ingredient is selected so the unit is consistent
  static List<LossBar> byDay(List<LossRecord> records) {
    final declared = <String, double>{};
    final unexplained = <String, double>{};
    final units = <String, String>{};

    for (final r in records) {
      final day = _dayKey(r.occurredAt);
      units[day] = r.unitOfMeasure;

      if (r.category == LossCategory.declared) {
        declared[day] = (declared[day] ?? 0) + r.quantity;
      } else {
        unexplained[day] = (unexplained[day] ?? 0) + r.quantity;
      }
    }

    final days = {...declared.keys, ...unexplained.keys}.toList()..sort();

    return days
        .map((day) => LossBar(
              // just the day and month on the axis, the full date is too wide
              label: day.substring(5),
              sortKey: day,
              declared: declared[day] ?? 0,
              unexplained: unexplained[day] ?? 0,
              unit: units[day] ?? '',
            ))
        .toList();
  }

  /// exact figures per ingredient in their own units, whatever the chart is showing
  static List<LossSummaryRow> summary(List<LossRecord> records) {
    final declared = <int, double>{};
    final unexplained = <int, double>{};
    final names = <int, String>{};
    final units = <int, String>{};

    for (final r in records) {
      names[r.ingredientId] = r.ingredientName;
      units[r.ingredientId] = r.unitOfMeasure;

      if (r.category == LossCategory.declared) {
        declared[r.ingredientId] = (declared[r.ingredientId] ?? 0) + r.quantity;
      } else {
        unexplained[r.ingredientId] =
            (unexplained[r.ingredientId] ?? 0) + r.quantity;
      }
    }

    final rows = names.keys
        .map((id) => LossSummaryRow(
              ingredientName: names[id]!,
              unitOfMeasure: units[id]!,
              declared: declared[id] ?? 0,
              unexplained: unexplained[id] ?? 0,
            ))
        .toList();

    rows.sort((a, b) => a.ingredientName.compareTo(b.ingredientName));
    return rows;
  }

  /// YYYY-MM-DD, sorts correctly as text
  static String _dayKey(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
