/// a row from transactions, one recorded sale
class Sale {
  final int transactionId;
  final int shiftId;
  final String transactionDatetime; // ISO-8601
  final double totalAmount;
  final bool isVoided;
  final int? voidedBy;
  // from a join, how many items were on the sale
  final int itemCount;
  // from a join, who was logged in for the shift
  final String cashierName;

  const Sale({
    required this.transactionId,
    required this.shiftId,
    required this.transactionDatetime,
    required this.totalAmount,
    required this.isVoided,
    required this.voidedBy,
    required this.itemCount,
    required this.cashierName,
  });

  factory Sale.fromMap(Map<String, Object?> map) {
    return Sale(
      transactionId: map['transaction_id'] as int,
      shiftId: map['shift_id'] as int,
      transactionDatetime: map['transaction_datetime'] as String,
      totalAmount: (map['total_amount'] as num).toDouble(),
      isVoided: (map['is_voided'] as int) == 1,
      voidedBy: map['voided_by'] as int?,
      // SUM gives null when a sale somehow has no items, treat that as 0
      itemCount: (map['item_count'] as num?)?.toInt() ?? 0,
      cashierName: map['cashier_name'] as String,
    );
  }
}

/// a row from transaction_items, uses the price snapshot not the current menu price
class SaleItem {
  final String menuItemName;
  final int quantity;
  final double unitPriceAtSale;
  final double lineTotal;

  const SaleItem({
    required this.menuItemName,
    required this.quantity,
    required this.unitPriceAtSale,
    required this.lineTotal,
  });

  factory SaleItem.fromMap(Map<String, Object?> map) {
    return SaleItem(
      menuItemName: map['menu_item_name'] as String,
      quantity: map['quantity'] as int,
      unitPriceAtSale: (map['unit_price_at_sale'] as num).toDouble(),
      lineTotal: (map['line_total'] as num).toDouble(),
    );
  }
}

/// one restored batch line, shown after a void so the barista can see where stock went back
class RestoredBatch {
  final int batchId;
  final String ingredientName;
  final double quantity;
  final String unitOfMeasure;

  const RestoredBatch({
    required this.batchId,
    required this.ingredientName,
    required this.quantity,
    required this.unitOfMeasure,
  });
}
