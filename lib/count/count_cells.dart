import '../data/count_line.dart';
import '../data/stock_item.dart';
import '../logic/count_math.dart';
import '../logic/formatting.dart';
import '../logic/units.dart';

// what the logbook cells show, the count tab and the history tab both use these so they always match

// the Unit cell, container items show both like "bottle • ml"
// number items show their piece name like "pack", or "pcs" when it is empty (display only)
String unitText(StockItem item) {
  if (item.countType == CountType.container) {
    return '${item.containerName} • ${item.baseUnit.name}';
  }
  return item.pieceName ?? item.baseUnit.name;
}

// a base amount the way the logbook shows it (rule 1)
// container items show in containers since that is how the barista thinks, 5500 ml on a 2000 ml bottle = "2.75"
// number items show in pcs
String shownAmount(StockItem item, double amount) {
  if (item.countType == CountType.container) {
    return formatAmount(amount / item.containerSize!);
  }
  return formatAmount(amount);
}

// what the Out column shows (rule 3)
// container items = containers finished
// number items = pieces used, worked out here and not saved, read only for now
// an opening count has no usage (rule 7) so it shows a dash, its Start of 0 would give a wrong number
String outText(StockItem item, CountLine line) {
  if (item.countType == CountType.container) return line.outCount.toString();
  if (line.isOpening) return '—';
  return formatAmount(
    amountUsed(start: line.startQty, inQty: line.inQty, end: line.endQty),
  );
}
