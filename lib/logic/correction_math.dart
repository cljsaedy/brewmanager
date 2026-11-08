import 'count_math.dart';
import 'units.dart';

// the math of a correction (rule 4), no db and no screens here so it is easy to test

// the count fields of a container line
class ContainerState {
  const ContainerState({
    required this.sealed,
    required this.level,
    required this.exactQty,
  });

  final int sealed;
  final double level;
  // typed exact amount for the opened container, null = the level is used
  final double? exactQty;

  @override
  bool operator ==(Object other) =>
      other is ContainerState &&
      other.sealed == sealed &&
      other.level == level &&
      other.exactQty == exactQty;

  @override
  int get hashCode => Object.hash(sealed, level, exactQty);

  @override
  String toString() => 'ContainerState($sealed, $level, $exactQty)';
}

// one IN or OUT event of the draft day, oldest first
class DayEvent {
  const DayEvent({required this.isRestock, required this.qty});

  // true = a restock, false = a finished container
  final bool isRestock;
  // base units for a restock, 1 for a finished container
  final double qty;
}

// what a replay gives back
class ReplayResult {
  const ReplayResult({required this.end, required this.beforeEachFinish});

  // the count fields after all the events
  final ContainerState end;
  // the fields right before each finished tap, in order
  // they go back on the OUT events so undo still knows what each tap changed
  final List<ContainerState> beforeEachFinish;
}

// when a correction changes yesterday's End, today's draft has to start from the new values
// if the barista never counted the item today, its fields came only from yesterday + today's taps,
// so they get rebuilt: start from the corrected values and do every IN and OUT again in order
// IN adds whole containers to sealed (restocks arrive sealed), OUT does what the finished button does (rule 3)
// this way no restock or finished tap is lost
ReplayResult replayDay({
  required ContainerState start,
  required List<DayEvent> events,
  required double containerSize,
}) {
  var state = start;
  final beforeEachFinish = <ContainerState>[];

  for (final event in events) {
    if (event.isRestock) {
      state = ContainerState(
        sealed: state.sealed + containersIn(event.qty, containerSize),
        level: state.level,
        exactQty: state.exactQty,
      );
    } else {
      beforeEachFinish.add(state);
      state = ContainerState(
        sealed: sealedAfterFinish(state.sealed),
        level: levelAfterFinish(state.sealed),
        exactQty: null,
      );
    }
  }
  return ReplayResult(end: state, beforeEachFinish: beforeEachFinish);
}

// the same for a number item: the corrected End + today's restocks
// an untouched number line is just what was carried over plus every IN
double replayNumber({required double start, required List<DayEvent> events}) {
  var total = start;
  for (final event in events) {
    if (event.isRestock) total += event.qty;
  }
  return roundAmount(total);
}
