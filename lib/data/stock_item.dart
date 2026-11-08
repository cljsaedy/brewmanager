import '../logic/formatting.dart';
import '../logic/units.dart';

// category saved when the owner leaves the category box empty
const String defaultCategory = 'Other';

// word shown when a container item has no container name typed, like "2 containers"
const String defaultContainerLabel = 'container';

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
    this.sizeUnit,
    this.lowUnit,
    this.isArchived = false,
    this.needsOpeningCount = false,
  });

  // null for a new item that is not saved yet, the db gives the id
  final int? id;
  final String name;
  // like 'Syrups' or 'Cups', typed by the owner, empty gets saved as 'Other'
  final String category;
  final BaseUnit baseUnit;
  final CountType countType;
  // like 'bottle' or 'pack', optional (null = not typed)
  // container items: the container's name, number items: what 1 piece is called on screens, like 'pack' (display only, still pcs)
  final String? containerLabel;
  // how much 1 full container holds in the base unit, like 2000 (ml), only for container items
  final double? containerSize;
  final LowMode lowMode;
  // the low-stock level, in containers or in base units depending on lowMode
  final double lowValue;
  // the unit the owner typed the size and the exact low level in, like 'L' or 'kg', display only
  // the amounts above are still in the base unit, null = typed in the base unit
  final String? sizeUnit;
  final String? lowUnit;
  final bool isArchived;
  // true after a restore, until the item's opening count is submitted (rule 3)
  final bool needsOpeningCount;

  // the container word to show on screens, 'container' when the owner left it empty
  String get containerName {
    final label = containerLabel?.trim() ?? '';
    return label.isEmpty ? defaultContainerLabel : label;
  }

  // what a number item's piece is called, the typed name or null when empty (screens show pcs then)
  String? get pieceName {
    final label = containerLabel?.trim() ?? '';
    return label.isEmpty ? null : label;
  }

  // the word next to an amount box: container items = the base unit, number items = "packs" or "pcs"
  String get unitWord {
    if (countType == CountType.container) return baseUnit.name;
    final piece = pieceName;
    return piece == null ? baseUnit.name : pluralOf(piece);
  }

  // the units the size and the exact low level were typed in, the base unit when none was saved
  InputUnit get sizeInputUnit => inputUnitFor(sizeUnit, baseUnit);
  InputUnit get lowInputUnit => inputUnitFor(lowUnit, baseUnit);

  // container size in the unit the owner typed, like "2 L"
  String get sizeText {
    final unit = sizeInputUnit;
    return formatWithUnit(fromBaseUnit(containerSize ?? 0, unit), unit.label);
  }

  // the low-stock level the way the owner typed it, like "1 bottle", "1 kg" or "5 packs"
  String get lowText {
    if (lowMode == LowMode.containers) {
      return formatContainers(lowValue, containerName);
    }
    final unit = lowInputUnit;
    if (unit.factor == 1) return amountText(this, lowValue);
    return formatWithUnit(fromBaseUnit(lowValue, unit), unit.label);
  }

  // the low-stock number for an edit box, in the typed unit, like 1 for 1000 g typed as kg
  double get lowShown {
    if (lowMode == LowMode.containers) return lowValue;
    return fromBaseUnit(lowValue, lowInputUnit);
  }

  // the word next to the low-stock box, like "bottles", "kg" or "packs"
  String get lowWord {
    if (lowMode == LowMode.containers) return pluralOf(containerName);
    final unit = lowInputUnit;
    return unit.factor == 1 ? unitWord : unit.label;
  }

  // a number typed in the low-stock box back to what gets saved, like 0.5 kg -> 500 g
  double lowFromShown(double shown) {
    if (lowMode == LowMode.containers) return shown;
    return toBaseUnit(shown, lowInputUnit, baseUnit);
  }

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
      sizeUnit: row['size_unit'] as String?,
      lowUnit: row['low_unit'] as String?,
      isArchived: row['is_archived'] == 1,
      needsOpeningCount: row['needs_opening_count'] == 1,
    );
  }

  // turns this item into a row for the db (id, is_archived and needs_opening_count are left out, the stores handle those)
  // number items never keep a container size, their label is just the piece name
  // empty category is saved as 'Other', empty container label is saved as null
  // a unit is only saved when it is not the base unit (null = base unit), and only where it is used:
  // size unit for container items, low unit for an exact low level
  Map<String, Object?> toRow() {
    final isContainer = countType == CountType.container;
    final cleanCategory = category.trim();
    final cleanLabel = containerLabel?.trim() ?? '';
    return {
      'name': name.trim(),
      'category': cleanCategory.isEmpty ? defaultCategory : cleanCategory,
      'base_unit': baseUnit.name,
      'count_type': countType.name,
      'container_label': cleanLabel.isNotEmpty ? cleanLabel : null,
      'container_size': isContainer ? containerSize : null,
      'low_mode': lowMode.name,
      'low_value': lowValue,
      'size_unit': isContainer && sizeInputUnit.factor != 1 ? sizeUnit : null,
      'low_unit': lowMode == LowMode.exact && lowInputUnit.factor != 1
          ? lowUnit
          : null,
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
    String? sizeUnit,
    String? lowUnit,
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
      sizeUnit: sizeUnit ?? this.sizeUnit,
      lowUnit: lowUnit ?? this.lowUnit,
      isArchived: isArchived,
      needsOpeningCount: needsOpeningCount,
    );
  }
}

// checks the stock item rules, gives back the first problem in plain words, or null if all good
// the store uses it before saving and the form uses it to show the message
String? stockItemProblem(StockItem item) {
  // category can be empty, toRow saves it as 'Other'
  if (item.name.trim().isEmpty) return 'Type a name.';

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
    // container label can be empty, screens show 'container' then
    final size = item.containerSize;
    if (size == null || size <= 0) {
      return 'Container size must be more than 0.';
    }
  }

  if (item.lowValue < 0) return 'Low-stock level cannot be below 0.';
  // a saved unit has to fit the base unit, kg for g, L or oz for ml (never g <-> ml, rule 1)
  for (final unit in [item.sizeUnit, item.lowUnit]) {
    if (unit != null &&
        !inputUnitsFor(item.baseUnit).any((u) => u.label == unit)) {
      return '$unit does not fit ${item.baseUnit.name}.';
    }
  }
  return null;
}

// an amount in base units with the word the barista knows
// number items with a piece name show it, like "6 packs", else the base unit, like "6 pcs" or "500 g"
String amountText(StockItem item, double amount) {
  final piece = item.countType == CountType.number ? item.pieceName : null;
  if (piece != null) return formatContainers(amount, piece);
  return formatWithUnit(amount, item.baseUnit.name);
}
