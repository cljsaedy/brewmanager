import 'package:flutter/material.dart';

import '../logic/clock_guard.dart';

/// shows the clock warning dialog once, over whatever screen the app starts on
///
/// dismissible because the cafe may need to keep trading, but the check runs again
/// every launch so it keeps nagging until the tablet's date is fixed
class ClockWarningGate extends StatefulWidget {
  const ClockWarningGate({
    super.key,
    required this.warning,
    required this.child,
  });

  final ClockWarning? warning;
  final Widget child;

  @override
  State<ClockWarningGate> createState() => _ClockWarningGateState();
}

class _ClockWarningGateState extends State<ClockWarningGate> {
  @override
  void initState() {
    super.initState();
    // can't show a dialog while the first frame is still being built, so wait for it
    if (widget.warning != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _show());
    }
  }

  Future<void> _show() async {
    final warning = widget.warning!;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.schedule_outlined,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
        title: const Text('Tablet clock looks wrong'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The tablet says it is earlier than the last activity already '
                'recorded — about ${warning.summary} behind.',
              ),
              const SizedBox(height: 12),
              Text('Device date: ${_fmt(warning.deviceNow)}'),
              Text('Last recorded: ${_fmt(warning.latestRecorded)}'),
              const SizedBox(height: 12),
              const Text(
                'While the date is wrong, expiry colours and the near-expiry '
                'suggestions will be wrong too, and new sales will be stamped '
                'with the wrong time.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Fix the tablet date in Android settings, then reopen '
                'BrewManager.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
