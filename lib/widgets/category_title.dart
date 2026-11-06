import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// small caramel title above each category group in the tables, like "SYRUPS"
class CategoryTitle extends StatelessWidget {
  const CategoryTitle(this.category, {super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        category.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.caramel,
        ),
      ),
    );
  }
}
