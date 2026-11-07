import 'count_math.dart';
import 'units.dart';

// the math of one day's report (rule 6 and rule 7), no db and no screens here so it is easy to test
// the app works out every number here, the ai only puts them into words later
// all amounts are in the stock item's base unit

// how one tallied menu item uses one stock item
// like 3 lattes with 30 ml of syrup each = RecipeUse(menuQty: 3, amount: 30)
class RecipeUse {
  const RecipeUse({required this.menuQty, required this.amount});

  // how many of the menu item were tallied
  final int menuQty;
  // how much of the stock item 1 menu item uses
  final double amount;
}

// expected usage of a stock item = each tallied menu item x its recipe amount, added up (rule 6)
// a menu item with no recipe has no RecipeUse so it adds nothing, it never gives a wrong number
double expectedUsage(List<RecipeUse> uses) {
  var total = 0.0;
  for (final use in uses) {
    total += use.menuQty * use.amount;
  }
  return roundAmount(total);
}

// true when the actual can be trusted to the exact amount
// a level button is only an estimate, so both ends of the day have to be exact (rule 7)
bool actualIsExact({required bool startIsExact, required bool endIsExact}) {
  return startIsExact && endIsExact;
}

// actual - expected, positive = more used than the tally explains, negative = less (rule 7)
// null when it cant be shown:
// - no actual (opening count)
// - no expected (item in no recipe)
// - estimated, a level tap is off by more than a small cafe uses in a day
double? gapOf({
  required double? actual,
  required double? expected,
  required bool isExact,
}) {
  if (actual == null || expected == null || !isExact) return null;
  return roundAmount(actual - expected);
}

// the results of one stock item on one day, same as a day_results row
class DayUsage {
  const DayUsage({
    required this.expected,
    required this.actual,
    required this.actualIsExact,
    required this.gap,
    required this.restockFlag,
  });

  // null on an opening count or when the item is in no recipe
  final double? expected;
  // null on an opening count, it only sets the starting stock
  final double? actual;
  final bool actualIsExact;
  // null unless it can be shown, see gapOf
  final double? gap;
  final bool restockFlag;
}

// works out all the results of one stock item on one day
// inRecipe = the item is in at least 1 recipe, even if nothing using it was tallied today
// that is why expected can be 0 here (in a recipe, nothing tallied) or null (in no recipe)
// an opening count gets no expected too, its count comes after that day's sales so they cant be compared
// the restock flag still works on an opening count since End is a real count
DayUsage dayUsage({
  required double start,
  required bool startIsExact,
  required double inQty,
  required double end,
  required bool endIsExact,
  required bool isOpening,
  required bool inRecipe,
  required List<RecipeUse> uses,
  required LowMode lowMode,
  required double lowValue,
  required double? containerSize,
}) {
  final restockFlag = isAtLowLevel(
    end: end,
    lowMode: lowMode,
    lowValue: lowValue,
    containerSize: containerSize,
  );

  if (isOpening) {
    return DayUsage(
      expected: null,
      actual: null,
      actualIsExact: false,
      gap: null,
      restockFlag: restockFlag,
    );
  }

  final expected = inRecipe ? expectedUsage(uses) : null;
  final actual = amountUsed(start: start, inQty: inQty, end: end);
  final isExact = actualIsExact(
    startIsExact: startIsExact,
    endIsExact: endIsExact,
  );

  return DayUsage(
    expected: expected,
    actual: actual,
    actualIsExact: isExact,
    gap: gapOf(actual: actual, expected: expected, isExact: isExact),
    restockFlag: restockFlag,
  );
}

// one earlier submitted day of a stock item, what a container check needs to look back
class PastDay {
  const PastDay({
    required this.date,
    required this.expected,
    required this.containersFinished,
    required this.isOpening,
    this.openedAmount = 0,
  });

  // YYYY-MM-DD
  final String date;
  // null when that day had no expected number
  final double? expected;
  final int containersFinished;
  final bool isOpening;
  // how much was in the opened container at that day's count, only used for an opening count
  final double openedAmount;
}

// the result of a container check, same as a container_checks row
class ContainerCheck {
  const ContainerCheck({
    required this.containers,
    required this.containerTotal,
    required this.expectedSinceLast,
    required this.sinceDate,
  });

  // containers finished today
  final int containers;
  // containers x container size, what was really used up
  final double containerTotal;
  // what the recipes explain, null when the item is in no recipe
  final double? expectedSinceLast;
  // the day the window starts after: the last finished container or the first count
  final String sinceDate;
}

// the real comparison for level-counted items (rule 7), only for days with a container finished
// null = no check today: nothing finished, or an opening count
//
// it adds up the expected of today and the days before, going back until the last day
// that finished a container or the opening count, that day itself is not added:
// - a finish day was already in the check of that day
// - an opening count has no expected
//
// the first check after an opening count is different since that container wasnt full when counting began
// like opening at 50% of a 2000 ml bottle, then 1 finished = only 1000 ml was used up
// so its total = the opened amount + container size x (containers finished - 1)
// later checks use container size x containers finished
// with nothing opened at the opening count the first finished one was a whole container,
// so that check uses the normal total too, otherwise it would say 0 ml were finished
//
// expectedToday = null means the item is in no recipe, so the check has no expected number
// a past day with no expected adds nothing
ContainerCheck? containerCheck({
  required String today,
  required int containersFinished,
  required bool isOpening,
  required double containerSize,
  required double? expectedToday,
  required List<PastDay> earlierDays,
}) {
  if (isOpening || containersFinished == 0) return null;

  // newest first, dates in YYYY-MM-DD sort right as text
  final newestFirst = [...earlierDays]
    ..sort((a, b) => b.date.compareTo(a.date));

  var expected = expectedToday ?? 0;
  var sinceDate = today;
  var containerTotal = containersFinished * containerSize;
  for (final day in newestFirst) {
    sinceDate = day.date;
    if (day.isOpening) {
      if (day.openedAmount > 0) {
        containerTotal =
            day.openedAmount + containerSize * (containersFinished - 1);
      }
      break;
    }
    if (day.containersFinished > 0) break;
    expected += day.expected ?? 0;
  }

  return ContainerCheck(
    containers: containersFinished,
    containerTotal: roundAmount(containerTotal),
    expectedSinceLast: expectedToday == null ? null : roundAmount(expected),
    sinceDate: sinceDate,
  );
}
