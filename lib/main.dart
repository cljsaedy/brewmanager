import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/database_helper.dart';
import 'layout/app_layout.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // to setup connection from flutter to android before runApp(), needed for the orientation lock below
  WidgetsFlutterBinding.ensureInitialized();

  // set landscape orientation since the app is landscape only
  // (the manifest also has sensorLandscape so it doesnt flash portrait on start)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // hide the status bar and nav bar, swipe from the edge shows them for a bit then they hide again
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // open the database before showing anything, makes the tables on the very first launch
  await DatabaseHelper.database;

  runApp(const BrewManagerApp());
}

class BrewManagerApp extends StatelessWidget {
  const BrewManagerApp({super.key, this.home = const AppLayout()});

  // barista has no login so the app opens straight to the app layout (count tab)
  // tests pass their own layout here so it doesnt open the real database
  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrewManager',
      // hide the red "debug" ribbon on the top right
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // lets the app layout know when the owner section closes
      navigatorObservers: [appRouteObserver],
      home: home,
    );
  }
}
