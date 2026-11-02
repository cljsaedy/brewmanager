import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../theme/app_theme.dart';
import 'owner_section_screen.dart';
import 'pin_screen_frame.dart';

// shows the new recovery code once, the owner has to write it down or screenshot it
class RecoveryCodeScreen extends StatelessWidget {
  const RecoveryCodeScreen({super.key, required this.code, required this.db});

  // the plain code, only lives in memory while this screen is open
  final String code;
  // passed on to the owner section after "I saved it"
  final Database db;

  @override
  Widget build(BuildContext context) {
    // PopScope canPop false = the back button does nothing here, so the code cant be skipped by accident
    return PopScope(
      canPop: false,
      child: PinScreenFrame(
        icon: Icons.verified_user_outlined,
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
                MaterialPageRoute(builder: (_) => OwnerSectionScreen(db: db)),
              );
            },
            child: const Text('I saved it'),
          ),
        ],
        right: SizedBox(
          width: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Recovery code',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              // code sits in a cream box with a caramel border so it stands out
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                  border: Border.all(color: AppColors.caramel, width: 1.5),
                ),
                // SelectableText = the owner can long press to copy it
                child: SelectableText(
                  code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: AppColors.espresso,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Shown only once',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
