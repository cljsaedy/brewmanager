import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// owner side, only reachable through the pin
// "unlocked" is not saved anywhere: the owner is unlocked only while this screen is open,
// so leaving it in any way (lock button, back, home) means the pin is needed again
class OwnerSectionScreen extends StatefulWidget {
  const OwnerSectionScreen({super.key});

  @override
  State<OwnerSectionScreen> createState() => _OwnerSectionScreenState();
}

class _OwnerSectionScreenState extends State<OwnerSectionScreen> {
  // listens for the app going to the background
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // onHide = app is no longer on screen (home button, switched apps), lock right away
    _lifecycle = AppLifecycleListener(onHide: _lock);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  // close everything on top of the barista side, that is the lock
  void _lock() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // no barista top bar here, the owner section has its own header
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 68,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text('Owner', style: text.titleMedium)),
                    OutlinedButton.icon(
                      onPressed: _lock,
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text('Lock and exit'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // placeholder until the owner tabs get built
              Expanded(
                child: Card(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Owner section', style: text.headlineSmall),
                        const SizedBox(height: 6),
                        Text(
                          'Analytics, Reports, Menu & Recipes, Stock Items and '
                          'Settings come in later features.',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
