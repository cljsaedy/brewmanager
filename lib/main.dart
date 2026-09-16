import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database/database_helper.dart';
import 'database/user_repository.dart';
import 'screens/change_pin_screen.dart';
import 'screens/pin_entry_screen.dart';
import 'session/idle_lock.dart';
import 'session/session.dart';

Future<void> main() async {
  // to setup connection from flutter to android before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // set landscape orientation since the app is landscape only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // open db now (creates it on first launch) so screens can assume it's ready
  await DatabaseHelper.instance.database;

  // first launch check, if manager still has default pin force the change screen
  final managerNeedingNewPin =
      await UserRepository().findManagerWithDefaultPin();

  final Widget startScreen = managerNeedingNewPin != null
      ? ChangePinScreen(user: managerNeedingNewPin)
      : const PinEntryScreen();

  runApp(BrewManagerApp(home: startScreen));
}

/// root widget, everything else is under this
class BrewManagerApp extends StatelessWidget {
  const BrewManagerApp({super.key, required this.home});

  /// first screen to show, decided in main() before the app starts
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrewManager',
      debugShowCheckedModeBanner: false,
      // so Session.logOut() can navigate without a BuildContext
      navigatorKey: Session.navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      // builder wraps every screen so the idle timer sees all touches
      builder: (context, child) => IdleLock(child: child!),
      home: home,
    );
  }
}
