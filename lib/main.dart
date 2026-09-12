import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  runApp(const BrewManagerApp());
}

/// The root widget of the app. Everything else is a descendant of this.
class BrewManagerApp extends StatelessWidget {
  const BrewManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrewManager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
      ),
      // Temporary placeholder. Replaced by the PIN entry screen in a later step.
      home: const _PlaceholderScreen(),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'BrewManager',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
