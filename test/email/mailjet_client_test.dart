import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:brewmanager/email/mailjet_client.dart';

// MockClient = a fake http client from the http package, nothing goes to the internet
void main() {
  const success =
      '{"Messages":[{"Status":"success","To":[{"Email":"owner@example.com",'
      '"MessageID":1}]}]}';

  Future<void> sendWith(http.Client client) {
    return MailjetClient(client, 'test-key', 'test-secret').send(
      from: 'reports@example.com',
      to: 'owner@example.com',
      subject: 'Daily count for Mon, Nov 2',
      html: '<p>Hi</p>',
    );
  }

  test('sends the email the way the docs say', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return http.Response(success, 200);
    });

    await sendWith(client);

    expect(sent.url.toString(), mailjetUrl);
    expect(
      sent.headers['Authorization'],
      'Basic ${base64Encode(utf8.encode('test-key:test-secret'))}',
    );
    final message = (jsonDecode(sent.body)['Messages'] as List).single;
    expect(message['From'], {
      'Email': 'reports@example.com',
      'Name': senderName,
    });
    expect(message['To'], [
      {'Email': 'owner@example.com'},
    ]);
    expect(message['Subject'], 'Daily count for Mon, Nov 2');
    expect(message['HTMLPart'], '<p>Hi</p>');
  });

  test('a wrong key throws with mailjet answer', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"ErrorMessage":"API key authentication'
        '/authorization failure"}',
        401,
      ),
    );

    await expectLater(
      sendWith(client),
      throwsA(
        isA<MailjetException>().having(
          (error) => error.message,
          'message',
          allOf(contains('401'), contains('authentication')),
        ),
      ),
    );
  });

  test('a 200 where the message is not success throws', () async {
    final client = MockClient(
      (_) async => http.Response('{"Messages":[{"Status":"error"}]}', 200),
    );

    await expectLater(sendWith(client), throwsA(isA<MailjetException>()));
  });

  test('an answer that is not json throws', () async {
    final client = MockClient((_) async => http.Response('oops', 200));

    await expectLater(sendWith(client), throwsA(isA<MailjetException>()));
  });

  test('no internet comes out as the http error', () async {
    final client = MockClient(
      (_) async => throw http.ClientException('Failed host lookup'),
    );

    await expectLater(sendWith(client), throwsA(isA<http.ClientException>()));
  });
}
