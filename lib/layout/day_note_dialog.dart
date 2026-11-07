import 'package:flutter/material.dart';

// the box for the day note, for things not about one item like "power outage at 3pm" (rule 9)
// it closes with the typed text, or null when cancelled so nothing gets saved
// stateful since the text box controller has to stay alive and get cleaned up
class DayNoteDialog extends StatefulWidget {
  const DayNoteDialog({super.key, required this.note});

  // the note saved so far, null when there is none
  final String? note;

  @override
  State<DayNoteDialog> createState() => _DayNoteDialogState();
}

class _DayNoteDialogState extends State<DayNoteDialog> {
  late final TextEditingController _box = TextEditingController(
    text: widget.note,
  );

  @override
  void dispose() {
    _box.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Day Note'),
      // scrolls so the keyboard cant push the buttons off the short landscape screen
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: TextField(
            key: const Key('day_note_box'),
            controller: _box,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Optional, like "power outage at 3pm"',
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_box.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
