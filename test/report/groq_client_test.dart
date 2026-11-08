import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:brewmanager/report/groq_client.dart';

// MockClient = a fake http client from the http package, nothing goes to the internet
void main() {
  // a groq answer with this text, the same shape as the real one
  http.Response answer(String text, {int status = 200}) {
    return http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': text},
            },
          ],
        }),
      ),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  test('sends the facts the way the docs say and reads the text', () async {
    late http.Request sent;
    final client = MockClient((request) async {
      sent = request;
      return answer('  2 items need restocking – see “notes”.  ');
    });

    final text = await GroqClient(
      client,
      'test-key',
    ).summarize('{"menu_items_tallied":2}');

    expect(text, '2 items need restocking – see “notes”.');
    expect(sent.url.toString(), groqUrl);
    expect(sent.headers['Authorization'], 'Bearer test-key');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], groqModel);
    expect(body['temperature'], 0);
    expect(body['max_completion_tokens'], groqMaxTokens);
    final messages = body['messages'] as List;
    expect(messages[0]['role'], 'system');
    expect(messages[0]['content'], contains('as digits'));
    expect(messages[1], {
      'role': 'user',
      'content': '{"menu_items_tallied":2}',
    });
  });

  test('an error answer throws', () async {
    final client = MockClient(
      (_) async =>
          http.Response('{"error":{"message":"Invalid API Key"}}', 401),
    );

    await expectLater(
      GroqClient(client, 'wrong').summarize('{}'),
      throwsA(
        isA<GroqException>().having(
          (error) => error.message,
          'message',
          contains('401'),
        ),
      ),
    );
  });

  test('an answer with no text throws', () async {
    final client = MockClient((_) async => answer('   '));

    await expectLater(
      GroqClient(client, 'test-key').summarize('{}'),
      throwsA(isA<GroqException>()),
    );
  });

  test('a strange answer throws instead of crashing', () async {
    final client = MockClient(
      (_) async => http.Response('{"choices":[]}', 200),
    );

    await expectLater(
      GroqClient(client, 'test-key').summarize('{}'),
      throwsA(isA<GroqException>()),
    );
  });
}
