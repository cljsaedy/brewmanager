import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../session/session.dart';

/// placeholder, increment 3 replaces this with the pos grid
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
      body: const Center(child: Text('Barista home (coming in Increment 3)')),
    );
  }
}
