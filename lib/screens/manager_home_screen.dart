import 'package:flutter/material.dart';

import '../models/app_user.dart';
import 'pin_entry_screen.dart';

/// Placeholder. Increment 2 replaces this with configuration and receiving.
class ManagerHomeScreen extends StatelessWidget {
  const ManagerHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manager — ${user.name}'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const PinEntryScreen()),
            ),
          ),
        ],
      ),
      body: const Center(child: Text('Manager home (coming in Increment 2)')),
    );
  }
}
