import '../logic/units.dart';

// one row of the stock_items table
class StockItem {
  const StockItem({
    this.id,
    required this.name,
    required this.category,
    required this.baseUnit,
    required this.countType,
    this.containerLabel,
    this.containerSize,
    required this.lowMode,
    required this.lowValue,
    this.isArchived = false,
  });

  // null for a new item that is not saved yet, the db gives the id
  final int? id;
  final String name;
  // like 'Syrups' or 'Cups', typed by the owner
  final String category;
  final BaseUnit baseUnit;
  final CountType countType;
  // like 'bottle' or 'pack', only for container items
  final String? containerLabel;
  // how much 1 full container holds in the base unit, like 2000 (ml), only for container items
  final double? containerSize;
  final LowMode lowMode;
  // the low-stock level, in containers or in base units depending on lowMode
  final double lowValue;
  final bool isArchived;

  // makes a StockItem from a db row
  // values.byName('g') = finds the enum value with that name
  factory StockItem.fromRow(Map<String, Object?> row) {
    return StockItem(
      id: row['id'] as int,
      name: row['name'] as String,
      category: row['category'] as String,
      baseUnit: BaseUnit.values.byName(row['base_unit'] as String),
      countType: CountType.values.byName(row['count_type'] as String),
      containerLabel: row['container_label'] as String?,
      // sqlite can give back a whole number as int, so read it as num then make it double
      containerSize: (row['container_size'] as num?)?.toDouble(),
      lowMode: LowMode.values.byName(row['low_mode'] as String),
      lowValue: (row['low_value'] as num).toDouble(),
      isArchived: row['is_archived'] == 1,
    );
  }

  // turns this item into a row for the db (id and is_archived are left out, the store handles those)
  // number items never keep a container label or size
  Map<String, Object?> toRow() {
    final isContainer = countType == CountType.container;
    return {
      'name': name.trim(),
      'category': category.trim(),
      'base_unit': baseUnit.name,
      'count_type': countType.name,
      'container_label': isContainer ? containerLabel?.trim() : null,
      'container_size': isContainer ? containerSize : null,
      'low_mode': lowMode.name,
      'low_value': lowValue,
    };
  }

  // copy of this item with some fields changed, used by the edit form
  StockItem copyWith({
    String? name,
    String? category,
    BaseUnit? baseUnit,
    CountType? countType,
    String? containerLabel,
    double? containerSize,
    LowMode? lowMode,
    double? lowValue,
  }) {
    return StockItem(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      baseUnit: baseUnit ?? this.baseUnit,
      countType: countType ?? this.countType,
      containerLabel: containerLabel ?? this.containerLabel,
      containerSize: containerSize ?? this.containerSize,
      lowMode: lowMode ?? this.lowMode,
      lowValue: lowValue ?? this.lowValue,
      isArchived: isArchived,
    );
  }
}

// checks the stock item rules, gives back the first problem in plain words, or null if all good
// the store uses it before saving and the form uses it to show the message
String? stockItemProblem(StockItem item) {
  if (item.name.trim().isEmpty) return 'Type a name.';
  if (item.category.trim().isEmpty) return 'Type a category.';

  if (item.countType == CountType.number) {
    // number items are whole pieces only (fries packs, wings, gloves)
    if (item.baseUnit != BaseUnit.pcs) {
      return 'Number items are counted in pcs.';
    }
    // no containers, so the low-stock level can only be an exact amount
    if (item.lowMode != LowMode.exact) {
      return 'Number items need an exact low-stock level.';
    }
  } else {
    final label = item.containerLabel?.trim() ?? '';
    if (label.isEmpty) {
      return 'Type what the container is, like bottle or pack.';
    }
    final size = item.containerSize;
    if (size == null || size <= 0) {
      return 'Container size must be more than 0.';
    }
  }

  if (item.lowValue < 0) return 'Low-stock level cannot be below 0.';
  return null;
}
