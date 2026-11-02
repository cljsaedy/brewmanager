import 'package:flutter/material.dart';

// temporary empty card for tabs that are not built yet (barista and owner side)
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(note, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
