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
