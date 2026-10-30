import '../database/batch_repository.dart';
import '../database/shift_repository.dart';
import '../logic/expiry_risk.dart';
import '../models/shift.dart';

/// what the home screens show across the top
///
/// the home screen's job is to answer "what is the state right now", so this
/// gathers the few numbers worth seeing on walking up to the tablet
class HomeStatus {
  final Shift? openShift;
  final ShiftSummary? shiftSummary;

  /// batches in the red band, expired or 48h or less
  final int urgentBatchCount;

  /// the soonest expiring ingredient with stock, for the one line of detail
  final String? soonestIngredient;
  final int? soonestDays;

  const HomeStatus({
    required this.openShift,
    required this.shiftSummary,
    required this.urgentBatchCount,
    required this.soonestIngredient,
    required this.soonestDays,
  });

  bool get hasOpenShift => openShift != null;
  bool get hasUrgentStock => urgentBatchCount > 0;
}

class HomeStatusService {
  HomeStatusService({ShiftRepository? shifts, BatchRepository? batches})
      : _shifts = shifts ?? ShiftRepository(),
        _batches = batches ?? BatchRepository();

  final ShiftRepository _shifts;
  final BatchRepository _batches;

  Future<HomeStatus> load() async {
    final openShift = await _shifts.getOpenShift();
    final summary = openShift == null
        ? null
        : await _shifts.getSummary(openShift.shiftId);

    // only batches with stock, an empty one can't be used up
    final batches = await _batches.getAllWithIngredient();
    final today = DateTime.now();

    var urgent = 0;
    String? soonestName;
    int? soonestDays;

    for (final item in batches) {
      final expiry = item.batch.expiryDate;
      if (ExpiryRisk.bandFor(expiry, today) == ExpiryBand.red) urgent++;

      final days = ExpiryRisk.daysUntil(expiry, today);
      if (soonestDays == null || days < soonestDays) {
        soonestDays = days;
        soonestName = item.ingredientName;
      }
    }

    return HomeStatus(
      openShift: openShift,
      shiftSummary: summary,
      urgentBatchCount: urgent,
      soonestIngredient: soonestName,
      soonestDays: soonestDays,
    );
  }
}
