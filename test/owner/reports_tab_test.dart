import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/email_settings_store.dart';
import 'package:brewmanager/data/sent_reports_store.dart';
import 'package:brewmanager/email/outbox_sender.dart';
import 'package:brewmanager/main.dart';
import 'package:brewmanager/owner/reports/reports_tab.dart';
import 'package:brewmanager/security/key_store.dart';

import '../helpers/tablet_screen.dart';
import '../helpers/test_database.dart';

void main() {
  late Database db;
  late MemoryKeyStore keys;
  // how many emails the fake mailjet got
  late int mailjetCalls;

  setUp(() async {
    db = await openTestDatabase(noIsolate: true);
    keys = MemoryKeyStore();
    mailjetCalls = 0;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addDay(String date) {
    return db.insert('business_days', {
      'business_date': date,
      'status': 'submitted',
    });
  }

  Future<int> queue(
    String kind,
    int? dayId, {
    String status = 'queued',
    String? error,
    String createdAt = '2026-11-02T10:00:00.000Z',
  }) {
    return db.insert('outbox', {
      'kind': kind,
      'day_id': dayId,
      'subject': 'Subject $kind',
      'html_body': '<p>$kind body</p>',
      'status': status,
      'last_error': error,
      'created_at': createdAt,
    });
  }

  // a fake mailjet that takes every email
  http.Client mailjetOk() {
    return MockClient((_) async {
      mailjetCalls++;
      return http.Response('{"Messages":[{"Status":"success"}]}', 200);
    });
  }

  // the tab reads the db on its own, so give it real time
  Future<void> waitForDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openReports(WidgetTester tester, {http.Client? client}) async {
    useTabletScreen(tester);
    await tester.pumpWidget(
      BrewManagerApp(
        home: Scaffold(
          body: ReportsTab(
            store: SentReportsStore(db),
            sender: OutboxSender(db, keys, client ?? mailjetOk()),
            // a webview cant run in tests, this shows the html as text
            viewer: (html) => Text(html, key: const Key('email_html')),
          ),
        ),
      ),
    );
    await waitForDb(tester);
  }

  testWidgets('no emails yet says so', (tester) async {
    await openReports(tester);

    expect(find.text('No reports yet'), findsOneWidget);
  });

  testWidgets('lists daily and correction emails, newest first, no recovery', (
    tester,
  ) async {
    final nov2 = await addDay('2026-11-02');
    await queue('daily', nov2, status: 'sent');
    await queue(
      'correction',
      nov2,
      createdAt: '2026-11-03T10:00:00.000Z',
      status: 'failed',
      error: 'HTTP 401: bad key',
    );
    await queue('recovery', null, createdAt: '2026-11-04T10:00:00.000Z');

    await openReports(tester);

    expect(find.text('Daily report'), findsOneWidget);
    expect(find.text('Correction'), findsOneWidget);
    expect(find.text('Subject recovery'), findsNothing);
    // the newest (the correction) is open, with mailjet's reason
    expect(find.text('<p>correction body</p>'), findsOneWidget);
    expect(find.text('HTTP 401: bad key'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('tapping an email shows it', (tester) async {
    final nov2 = await addDay('2026-11-02');
    final daily = await queue('daily', nov2, status: 'sent');
    await queue('correction', nov2, createdAt: '2026-11-03T10:00:00.000Z');
    await openReports(tester);

    await tester.tap(find.byKey(Key('report_$daily')));
    await tester.pumpAndSettle();

    expect(find.text('<p>daily body</p>'), findsOneWidget);
  });

  testWidgets('resend sends it and the status changes to sent', (tester) async {
    await EmailSettingsStore(db, keys).saveEmails(
      ownerEmail: 'owner@example.com',
      senderEmail: 'reports@example.com',
    );
    keys.values[ApiKey.mailjetKey] = 'test-key';
    keys.values[ApiKey.mailjetSecret] = 'test-secret';
    final nov2 = await addDay('2026-11-02');
    await queue('daily', nov2, status: 'failed', error: 'HTTP 401: bad key');
    await openReports(tester);
    expect(find.text('Failed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('resend_button')));
    await waitForDb(tester);

    expect(mailjetCalls, 1);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.byKey(const Key('report_error')), findsNothing);
  });

  testWidgets('no settings: resend says to set them', (tester) async {
    final nov2 = await addDay('2026-11-02');
    await queue('daily', nov2);
    await openReports(tester);

    await tester.tap(find.byKey(const Key('resend_button')));
    await waitForDb(tester);

    expect(mailjetCalls, 0);
    expect(
      find.text('Waiting: set the emails and Mailjet keys in Settings.'),
      findsOneWidget,
    );
  });
}
