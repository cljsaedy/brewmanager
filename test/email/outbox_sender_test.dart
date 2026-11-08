import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/email_settings_store.dart';
import 'package:brewmanager/email/outbox_sender.dart';
import 'package:brewmanager/security/key_store.dart';

import '../helpers/test_database.dart';

void main() {
  late Database db;
  late MemoryKeyStore keys;
  // how many emails the fake mailjet got, and what they were
  late List<Map<String, dynamic>> sent;

  setUp(() async {
    db = await openTestDatabase();
    keys = MemoryKeyStore();
    sent = [];
  });

  tearDown(() async {
    await db.close();
  });

  // owner + sender emails and both mailjet keys, everything sending needs
  Future<void> setUpSettings() async {
    await EmailSettingsStore(db, keys).saveEmails(
      ownerEmail: 'owner@example.com',
      senderEmail: 'reports@example.com',
    );
    keys.values[ApiKey.mailjetKey] = 'test-key';
    keys.values[ApiKey.mailjetSecret] = 'test-secret';
  }

  Future<int> queue(String kind, {String body = '<p>report</p>'}) {
    return db.insert('outbox', {
      'kind': kind,
      'subject': 'Subject $kind',
      'html_body': body,
      'created_at': '2026-11-02T10:00:00.000Z',
    });
  }

  Future<Map<String, Object?>> rowOf(int id) async {
    return (await db.query('outbox', where: 'id = ?', whereArgs: [id])).single;
  }

  // a fake mailjet that takes every email
  http.Client mailjetOk() {
    return MockClient((request) async {
      sent.add((jsonDecode(request.body)['Messages'] as List).single);
      return http.Response('{"Messages":[{"Status":"success"}]}', 200);
    });
  }

  OutboxSender sender(http.Client client) {
    return OutboxSender(
      db,
      keys,
      client,
      clock: () => DateTime.utc(2026, 11, 2, 11),
    );
  }

  test('a queued email is sent', () async {
    await setUpSettings();
    final id = await queue('daily');

    await sender(mailjetOk()).sendAll();

    final row = await rowOf(id);
    expect(row['status'], 'sent');
    expect(row['attempts'], 1);
    expect(row['last_error'], isNull);
    expect(row['sent_at'], '2026-11-02T11:00:00.000Z');
    expect(sent.single['To'], [
      {'Email': 'owner@example.com'},
    ]);
    expect(sent.single['From']['Email'], 'reports@example.com');
    // a daily email keeps its body, the reports tab shows it later
    expect(row['html_body'], '<p>report</p>');
  });

  test('a recovery email is blanked after it is sent (rule 11)', () async {
    await setUpSettings();
    final id = await queue('recovery', body: '<h2>7KQ2-M9XA</h2>');

    await sender(mailjetOk()).sendAll();

    final row = await rowOf(id);
    expect(row['status'], 'sent');
    expect(row['html_body'], '');
    expect(sent.single['HTMLPart'], '<h2>7KQ2-M9XA</h2>');
  });

  test('no settings: nothing is sent and it says why', () async {
    final id = await queue('daily');

    await sender(mailjetOk()).sendAll();

    final row = await rowOf(id);
    expect(row['status'], 'queued');
    expect(row['attempts'], 0);
    expect(row['last_error'], OutboxSender.notSetError);
    expect(sent, isEmpty);
    expect(OutboxSender.statusOf(row).needsSettings, isTrue);
  });

  test('no internet: stays waiting and the run stops', () async {
    await setUpSettings();
    final first = await queue('daily');
    final second = await queue('correction');
    var calls = 0;
    final offline = MockClient((_) async {
      calls++;
      throw http.ClientException('Failed host lookup');
    });

    await sender(offline).sendAll();

    final row = await rowOf(first);
    expect(row['status'], 'queued');
    expect(row['attempts'], 1);
    expect(row['last_error'], startsWith('No internet: '));
    expect(OutboxSender.statusOf(row).state, EmailState.waiting);
    // no point trying the 2nd one offline
    expect(calls, 1);
    expect((await rowOf(second))['attempts'], 0);

    // internet is back
    await sender(mailjetOk()).sendAll();
    expect((await rowOf(first))['status'], 'sent');
    expect((await rowOf(second))['status'], 'sent');
  });

  test('mailjet says no: failed with why, tried again next time', () async {
    await setUpSettings();
    final id = await queue('daily');
    final refused = MockClient(
      (_) async => http.Response('{"ErrorMessage":"bad key"}', 401),
    );

    await sender(refused).sendAll();

    var row = await rowOf(id);
    expect(row['status'], 'failed');
    expect(row['last_error'], contains('HTTP 401'));
    expect(OutboxSender.statusOf(row).state, EmailState.failed);

    // the owner fixed the key
    await sender(mailjetOk()).sendAll();
    row = await rowOf(id);
    expect(row['status'], 'sent');
    expect(row['attempts'], 2);
  });

  test('2 runs at once send each email only once', () async {
    await setUpSettings();
    await queue('daily');
    await queue('correction');
    final client = mailjetOk();

    await Future.wait([sender(client).sendAll(), sender(client).sendAll()]);

    expect(sent, hasLength(2));
  });

  test('a sent email is never sent again', () async {
    await setUpSettings();
    await queue('daily');
    await sender(mailjetOk()).sendAll();

    await sender(mailjetOk()).sendAll();

    expect(sent, hasLength(1));
  });

  test('a long error is cut short', () async {
    await setUpSettings();
    final id = await queue('daily');
    final refused = MockClient((_) async => http.Response('x' * 2000, 500));

    await sender(refused).sendAll();

    expect(((await rowOf(id))['last_error'] as String).length, lessThan(520));
  });

  test('dailyStatus reads the day email', () async {
    final dayId = await db.insert('business_days', {
      'business_date': '2026-11-02',
    });
    await db.insert('outbox', {
      'kind': 'daily',
      'day_id': dayId,
      'subject': 's',
      'html_body': 'b',
      'status': 'sent',
      'created_at': '2026-11-02T10:00:00.000Z',
    });

    final status = await sender(mailjetOk()).dailyStatus(dayId);
    expect(status!.state, EmailState.sent);
    expect(await sender(mailjetOk()).dailyStatus(dayId + 1), isNull);
  });

  test('resend sends a sent email again', () async {
    await setUpSettings();
    final id = await queue('daily');
    await sender(mailjetOk()).sendAll();

    await sender(mailjetOk()).resend(id);

    expect(sent, hasLength(2));
    final row = await rowOf(id);
    expect(row['status'], 'sent');
    expect(row['attempts'], 2);
  });

  test('a recovery email is never resent', () async {
    await setUpSettings();
    final id = await queue('recovery', body: '<h2>7KQ2-M9XA</h2>');
    await sender(mailjetOk()).sendAll();

    await sender(mailjetOk()).resend(id);

    expect(sent, hasLength(1));
    expect((await rowOf(id))['status'], 'sent');
  });
}
