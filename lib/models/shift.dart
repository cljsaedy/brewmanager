/// a row from shift_sessions, one stretch of trading by one person
///
/// shifts exist rather than just dates because a cafe with rotating staff
/// reconciles more than once a day
class Shift {
  final int shiftId;
  final int userId;
  final String userName; // from a join
  final String openedAt; // ISO-8601
  final String? closedAt; // null while still open
  final bool isOpen;

  const Shift({
    required this.shiftId,
    required this.userId,
    required this.userName,
    required this.openedAt,
    required this.closedAt,
    required this.isOpen,
  });

  factory Shift.fromMap(Map<String, Object?> map) {
    return Shift(
      shiftId: map['shift_id'] as int,
      userId: map['user_id'] as int,
      userName: map['user_name'] as String,
      openedAt: map['opened_at'] as String,
      closedAt: map['closed_at'] as String?,
      isOpen: (map['status'] as String) == 'open',
    );
  }
}

/// what happened during a shift, for the shift card and the closing summary
class ShiftSummary {
  final int saleCount;
  final double salesTotal;
  final int voidedCount;
  final int declaredLossCount;

  const ShiftSummary({
    required this.saleCount,
    required this.salesTotal,
    required this.voidedCount,
    required this.declaredLossCount,
  });

  factory ShiftSummary.fromMap(Map<String, Object?> map) {
    return ShiftSummary(
      // COUNT is never null but SUM is when there are no rows, so default those
      saleCount: (map['sale_count'] as num?)?.toInt() ?? 0,
      salesTotal: (map['sales_total'] as num?)?.toDouble() ?? 0,
      voidedCount: (map['voided_count'] as num?)?.toInt() ?? 0,
      declaredLossCount: (map['loss_count'] as num?)?.toInt() ?? 0,
    );
  }
}
