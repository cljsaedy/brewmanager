import 'package:flutter/material.dart';

import '../data/count_line.dart';
import '../widgets/status_chip.dart';

// badge of an item on its opening count day (rule 3)
const String openingCountBadge = 'Opening count: please count';

// badge of an item at or below its low-stock level, only a mark (rule 8)
const String restockBadge = 'Restock recommended';

// the badges of one count row, the table and the panel both show these
// Wrap = they go under each other when both dont fit
class CountBadges extends StatelessWidget {
  const CountBadges(this.row, {super.key});

  final CountRow row;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (row.line.isOpening)
          const StatusChip(label: openingCountBadge, tone: ChipTone.warn),
        if (row.restockRecommended)
          const StatusChip(label: restockBadge, tone: ChipTone.warn),
      ],
    );
  }
}
