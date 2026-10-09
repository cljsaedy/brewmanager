import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../session/session.dart';
import 'pos_screen.dart';

/// barista landing, the till is the main thing they do so it's one tap away
class BaristaHomeScreen extends StatelessWidget {
  const BaristaHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Barista — ${user.name}'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: Session.logOut,
          ),
        ],
      ),
      body: Center(
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PosScreen()),
          ),
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Open Point of Sale'),
        ),
      ),
    );
  }
}
