import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database/database_helper.dart';
import 'database/user_repository.dart';
import 'screens/change_pin_screen.dart';
import 'screens/pin_entry_screen.dart';

Future<void> main() async {
  // Flutter normally connects to the Android system inside runApp().
  // Because we need to talk to Android *before* that (to lock orientation),
  // we have to set up that connection explicitly first.
  WidgetsFlutterBinding.ensureInitialized();

  // BrewManager runs on a tablet in landscape only. Listing only the two
  // landscape orientations means Android will never rotate the app to
  // portrait, no matter how the tablet is tilted.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Open (and on first launch, create) the database before the UI appears,
  // so every screen can assume it is ready.
  await DatabaseHelper.instance.database;

  // First-launch check: if the seeded Manager still has the default PIN,
  // the only thing the app will show is the change-PIN screen.
  final managerNeedingNewPin =
      await UserRepository().findManagerWithDefaultPin();

  final Widget startScreen = managerNeedingNewPin != null
      ? ChangePinScreen(user: managerNeedingNewPin)
      : const PinEntryScreen();

  runApp(BrewManagerApp(home: startScreen));
}

/// The root widget of the app. Everything else is a descendant of this.
class BrewManagerApp extends StatelessWidget {
  const BrewManagerApp({super.key, required this.home});

  /// The first screen shown, decided in main() before the app starts.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrewManager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      home: home,
    );
  }
}
