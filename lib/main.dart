import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  runApp(const BrewManagerApp());
}

class BrewManagerApp extends StatelessWidget {
  const BrewManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BrewManager',
      // hide the red "debug" ribbon on the top right
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const PlaceholderHome(),
    );
  }
}

// temporary screen just to check the theme on the tablet, gets replaced by the app shell in step 1b
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 420,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                // column only as tall as its content
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BrewManager', style: text.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Theme check', style: text.bodySmall),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      FilledButton(onPressed: () {}, child: const Text('Submit')),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Day Note'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
