import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// draws an opened-container total as containers
///
/// the audit asks for one number covering everything left in opened containers,
/// but "1¾" is abstract, you have to translate what is on the shelf into a
/// fraction before you can enter it
///
/// drawing it as one full carton plus one three-quarter carton means the barista
/// can check the number against what they are holding instead of doing the
/// arithmetic in their head
class ContainerFill extends StatelessWidget {
  const ContainerFill({super.key, required this.total});

  /// the opened total, in containers, so 1.75 is one full and one three quarters
  final double total;

  /// past this many it stops drawing and says how many more there are, a row of
  /// twenty glyphs would not tell anyone anything
  static const int maxGlyphs = 6;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) {
      return const _Glyph(fill: 0);
    }

    final fullCount = total.floor();
    final remainder = total - fullCount;

    // one glyph per full container, plus one part filled glyph if there's a remainder
    final glyphs = <double>[
      for (var i = 0; i < fullCount; i++) 1.0,
      if (remainder > 0) remainder,
    ];

    final shown = glyphs.take(maxGlyphs).toList();
    final hidden = glyphs.length - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final fill in shown)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _Glyph(fill: fill),
          ),
        if (hidden > 0)
          Text(
            '+$hidden',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// one container, outlined and filled from the bottom like a carton would be
class _Glyph extends StatelessWidget {
  const _Glyph({required this.fill});

  /// 0 to 1
  final double fill;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 34,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(3),
      ),
      // the fill grows upward from the bottom, 2px inset so the outline stays visible
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: fill.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
