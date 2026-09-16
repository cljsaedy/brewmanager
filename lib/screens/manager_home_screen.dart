import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../session/session.dart';

/// placeholder, increment 2 replaces this with config and receiving
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
            onPressed: Session.logOut,
          ),
        ],
      ),
      body: const Center(child: Text('Manager home (coming in Increment 2)')),
    );
  }
}
