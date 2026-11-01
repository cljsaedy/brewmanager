import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'owner_section_screen.dart';
import 'pin_screen_frame.dart';

// shows the new recovery code once, the owner has to write it down or screenshot it
class RecoveryCodeScreen extends StatelessWidget {
  const RecoveryCodeScreen({super.key, required this.code});

  // the plain code, only lives in memory while this screen is open
  final String code;

  @override
  Widget build(BuildContext context) {
    // PopScope canPop false = the back button does nothing here, so the code cant be skipped by accident
    return PopScope(
      canPop: false,
      child: PinScreenFrame(
        title: 'Save your recovery code',
        message:
            'If you forget the PIN, this code lets you set a new one. '
            'Write it down or take a screenshot now. '
            'It will not be shown again.',
        showCancel: false,
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const OwnerSectionScreen()),
              );
            },
            child: const Text('I saved it'),
          ),
        ],
        right: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Recovery code',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              // SelectableText = the owner can long press to copy it
              SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppColors.espresso,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
