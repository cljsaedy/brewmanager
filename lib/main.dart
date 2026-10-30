import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'database/activity_repository.dart';
import 'database/database_helper.dart';
import 'database/user_repository.dart';
import 'logic/clock_guard.dart';
import 'screens/change_pin_screen.dart';
import 'screens/pin_entry_screen.dart';
import 'session/idle_lock.dart';
import 'session/session.dart';
import 'theme/app_theme.dart';
import 'widgets/clock_warning_banner.dart';

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

  // the newest timestamp in the db is a floor on what "now" can be, if the device
  // says earlier than that the tablet's date was changed or reset
  final clockWarning = ClockGuard.check(
    DateTime.now(),
    await ActivityRepository().latestRecordedActivity(),
  );

  runApp(BrewManagerApp(home: startScreen, clockWarning: clockWarning));
}

/// root widget, everything else is under this
class BrewManagerApp extends StatelessWidget {
  const BrewManagerApp({super.key, required this.home, this.clockWarning});

  /// first screen to show, decided in main() before the app starts
  final Widget home;

  /// set when the tablet's clock looks like it moved backwards, null when it's fine
  final ClockWarning? clockWarning;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrewManager',
      debugShowCheckedModeBanner: false,
      // so Session.logOut() can navigate without a BuildContext
      navigatorKey: Session.navigatorKey,
      theme: AppTheme.build(),
      // builder wraps every screen so the idle timer sees all touches
      builder: (context, child) => IdleLock(child: child!),
      // the gate just shows the warning dialog once, then gets out of the way
      home: ClockWarningGate(warning: clockWarning, child: home),
    );
  }
}
