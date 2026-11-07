import 'dart:math';

import 'units.dart';

// the math of one count (rule 2), no db and no screens here so it is easy to test

// the opened level buttons, as a part of 1 container
// a level is only an estimate, used as a restock signal, never an exact measurement
const double levelNone = 0;
const double levelAlmostEmpty = 0.1;
const double level25 = 0.25;
const double level50 = 0.5;
const double level75 = 0.75;
const double levelFull = 1;

// end of a container item, in base units
// end = sealed x container size + the opened part
// the opened part is the exact amount if one was typed, otherwise level x container size
// like 2 sealed + 50% of a 2000 ml bottle = 5000 ml
double containerEnd({
  required int sealed,
  required double containerSize,
  required double level,
  required double? exactQty,
}) {
  final opened = exactQty ?? level * containerSize;
  return roundAmount(sealed * containerSize + opened);
}

// true when a container count has no level part in it (rule 2):
// an exact amount was typed, or no container is open (only sealed ones)
// any other level button makes it estimated
// this gets saved with every End since the next day's Start inherits it
bool containerIsExact({required double level, required double? exactQty}) {
  return exactQty != null || level == levelNone;
}

// true when End is at or below the low-stock level (rule 8)
// a level in containers is turned into base units first, like below 2 bottles of 2000 ml = 4000 ml
// container size can be null for exact mode since it is not needed there
bool isAtLowLevel({
  required double end,
  required LowMode lowMode,
  required double lowValue,
  required double? containerSize,
}) {
  final limit = lowMode == LowMode.containers
      ? roundAmount(lowValue * containerSize!)
      : lowValue;
  return end <= limit;
}

// how many whole containers a restock is, restocks are saved in base units (rule 1)
// like 4000 ml with 2000 ml bottles = 2
int containersIn(double qty, double containerSize) {
  return (qty / containerSize).round();
}

// sealed after a restock is removed, it stops at 0
// the barista could have opened those containers already, so there may be fewer left than the restock added
int sealedAfterRemove(int sealed, int containers) {
  return max(0, sealed - containers);
}

// sealed after one tap on container finished (rule 3)
// staff finish one container before opening the next, so a sealed one gets opened
// with no sealed left it stays 0
int sealedAfterFinish(int sealed) {
  return max(0, sealed - 1);
}

// opened level after one tap on container finished, give it the sealed from before the tap
// a sealed one was just opened = full, nothing sealed left = no container open
double levelAfterFinish(int sealedBefore) {
  return sealedBefore > 0 ? levelFull : levelNone;
}

// true when there is something to finish, a sealed one or an open one
// no sealed, opened none and no typed amount = nothing is there (rule 3)
bool canFinishContainer({
  required int sealed,
  required double level,
  required double? exactQty,
}) {
  return sealed > 0 || level != levelNone || exactQty != null;
}

// sealed after undoing a finished tap, give it the sealed from now and from before that tap
// it only goes up if that tap really took one out, with 0 sealed the tap took nothing
// this adds to the sealed from now so restocks and edits after the tap stay in
int sealedAfterUndo({required int sealed, required int sealedBefore}) {
  return sealedBefore > 0 ? sealed + 1 : sealed;
}

// true when opened is still what the finished tap set, so undo can put the old one back
// anything else means the barista changed it after the tap, then undo leaves it alone
bool openedStillFromFinish({
  required double level,
  required double? exactQty,
  required int sealedBefore,
}) {
  return exactQty == null && level == levelAfterFinish(sealedBefore);
}

// how much of an item was used in one day, in base units (rule 7)
// used = start + in - end, like fries 8 at the start, none in, 6 at the end = 2 used
// it can go below 0 when the barista counts more than the logbook says was there
// dont use this on an opening count, its Start is 0 so the answer means nothing (rule 3)
double amountUsed({
  required double start,
  required double inQty,
  required double end,
}) {
  return roundAmount(start + inQty - end);
}
