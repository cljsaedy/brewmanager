import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/count_store.dart';
import '../data/database_helper.dart';
import '../data/email_settings_store.dart';
import '../data/owner_pin_store.dart';
import '../email/outbox_sender.dart';
import '../layout/app_layout.dart';
import '../logic/business_day.dart';
import '../logic/formatting.dart';
import '../owner/create_pin_screen.dart';
import '../owner/settings/settings_tab.dart';
import '../security/key_store.dart';
import '../theme/app_theme.dart';

// the first screen of the app
// no owner pin yet = a fresh install, so the setup wizard runs, otherwise straight to the count tab
// the wizard is only 3 steps: owner pin, emails and keys (can skip), first count date
// stock items and the menu are added in the owner section afterwards (decided with the developer)
class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    this.openDatabase = _realDatabase,
    this.keys,
    this.httpClient,
    this.barista = _realLayout,
  });

  // the app's db, tests pass their own
  final Future<Database> Function() openDatabase;
  // null = the real secure storage and a real http client, tests pass fakes
  final KeyStore? keys;
  final http.Client? httpClient;
  // the barista side to open, tests pass their own app layout
  final Widget Function() barista;

  static Future<Database> _realDatabase() => DatabaseHelper.database;
  static Widget _realLayout() => const AppLayout();

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  Database? _db;
  // null while checking
  bool? _hasPin;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final db = await widget.openDatabase();
    final hasPin = await OwnerPinStore(db).hasPin();
    if (!mounted) return;
    setState(() {
      _db = db;
      _hasPin = hasPin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = _hasPin;
    if (hasPin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (hasPin) return widget.barista();
    return WelcomeScreen(
      db: _db!,
      keys: widget.keys,
      httpClient: widget.httpClient,
      barista: widget.barista,
    );
  }
}

// the wizard's first screen, says what the 3 steps are
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.db,
    required this.barista,
    this.keys,
    this.httpClient,
  });

  final Database db;
  final KeyStore? keys;
  final http.Client? httpClient;
  final Widget Function() barista;

  // step 1: the normal create pin screens, then step 2 once the code was saved
  // the plain code goes along in memory, step 2 emails it once the owner email is saved
  void _start(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePinScreen(
          store: OwnerPinStore(db),
          onCodeSaved: (screenContext, code) {
            // pushReplacement = back cant go to the pin screens again, the pin is already set
            Navigator.of(screenContext).pushReplacement(
              MaterialPageRoute(
                builder: (_) => WizardEmailsScreen(
                  db: db,
                  code: code,
                  keys: keys,
                  httpClient: httpClient,
                  barista: barista,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _WizardFrame(
      children: [
        const Icon(Icons.coffee_outlined, size: 44, color: AppColors.caramel),
        const SizedBox(height: 12),
        Text('Welcome to BrewManager', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text('A quick setup before the first count:', style: text.bodyMedium),
        const SizedBox(height: 12),
        _step(text, '1', 'Owner PIN', 'Opens the owner section.'),
        _step(
          text,
          '2',
          'Emails and keys',
          'For the daily report. You can skip this.',
        ),
        _step(text, '3', 'First count date', 'Usually today.'),
        const SizedBox(height: 8),
        Text(
          'Stock items and the menu are added after this, in the owner section.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const Key('wizard_start'),
            onPressed: () => _start(context),
            child: const Text('Start'),
          ),
        ),
      ],
    );
  }

  Widget _step(TextTheme text, String number, String title, String note) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.cream,
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.espresso,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title. ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: note),
                ],
              ),
              style: text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// step 2: the owner settings email and keys part, with skip and save and continue
// back does nothing from here on, the pin is already set
class WizardEmailsScreen extends StatefulWidget {
  const WizardEmailsScreen({
    super.key,
    required this.db,
    required this.code,
    required this.barista,
    this.keys,
    this.httpClient,
  });

  final Database db;
  // the plain recovery code from step 1, only in memory, emailed once there is an owner email
  final String code;
  final KeyStore? keys;
  final http.Client? httpClient;
  final Widget Function() barista;

  @override
  State<WizardEmailsScreen> createState() => _WizardEmailsScreenState();
}

class _WizardEmailsScreenState extends State<WizardEmailsScreen> {
  late final KeyStore _keys = widget.keys ?? SecureKeyStore();
  late final EmailSettingsStore _store = EmailSettingsStore(widget.db, _keys);

  // after save and continue or skip: email the recovery code if an owner email is set now, then step 3
  // emailRecoveryCode does nothing when there is still no owner email (skipped)
  Future<void> _next() async {
    await OwnerPinStore(widget.db).emailRecoveryCode(widget.code);
    // send it now, the outbox keeps it if there is no internet (rule 10)
    unawaited(
      OutboxSender(
        widget.db,
        _keys,
        widget.httpClient ?? http.Client(),
      ).sendAll(),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => FirstDateScreen(db: widget.db, barista: widget.barista),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // PopScope canPop false = the back button does nothing, the wizard only goes forward
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SettingsTab(store: _store, onWizardNext: _next),
          ),
        ),
      ),
    );
  }
}

// step 3: the date of the first count, saved and used for the very first draft
// a count is for a day that already happened, so only today and earlier can be picked (rule 5)
class FirstDateScreen extends StatefulWidget {
  const FirstDateScreen({super.key, required this.db, required this.barista});

  final Database db;
  final Widget Function() barista;

  // how far back the first count date can go
  static const int maxDaysBack = 60;

  @override
  State<FirstDateScreen> createState() => _FirstDateScreenState();
}

class _FirstDateScreenState extends State<FirstDateScreen> {
  // YYYY-MM-DD, starts on today
  String _date = dateText(DateTime.now());
  bool _saving = false;

  Future<void> _pick() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: today.subtract(
        const Duration(days: FirstDateScreen.maxDaysBack),
      ),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _date = dateText(picked));
  }

  // saves the date, then opens the count tab with nothing behind it (back cant reach the wizard)
  Future<void> _finish() async {
    setState(() => _saving = true);
    await widget.db.insert('app_settings', {
      'key': CountStore.firstCountDateKey,
      'value': _date,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => widget.barista()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: _WizardFrame(
        children: [
          Text('Step 3 of 3', style: text.bodySmall),
          const SizedBox(height: 4),
          Text('First count date', style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'The first count sets the starting stock of every item '
            '(an opening count). Comparing starts with the count after it.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              formatLongDate(_date),
              key: const Key('first_date_text'),
              style: text.headlineMedium?.copyWith(color: AppColors.espresso),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const Key('first_date_change'),
              onPressed: _saving ? null : _pick,
              child: const Text('Change date'),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('wizard_finish'),
              onPressed: _saving ? null : _finish,
              child: const Text('Finish setup'),
            ),
          ),
        ],
      ),
    );
  }
}

// the shared look of the wizard's own screens: 1 card in the middle
class _WizardFrame extends StatelessWidget {
  const _WizardFrame({required this.children});

  final List<Widget> children;

  // widest the card gets
  static const double _maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
