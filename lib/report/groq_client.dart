import 'dart:convert';

import 'package:http/http.dart' as http;

// the groq chat api (openai style), called with the http package, no sdk (rule 10)
// docs: https://console.groq.com/docs/api-reference

const String groqUrl = 'https://api.groq.com/openai/v1/chat/completions';

// a current production model on groq, change it here if groq retires it
const String groqModel = 'llama-3.3-70b-versatile';

// the longest the app waits for groq, after this the template summary is used
const Duration groqTimeout = Duration(seconds: 20);

// enough room for about 120 words, the limit is in the instructions too
const int groqMaxTokens = 400;

// what the model is told, rule 10 plus the digits rule so the number check can trust every number
const String groqInstructions = '''
You write a short daily stock summary for the owner of a small cafe.
The user message is a JSON list of facts. The app already worked out every number.

Rules:
- Use only the facts given. Do not add anything that is not in them.
- Every number you write must be copied exactly from the facts, as digits (write 3, not three).
- Never write a number as a word. Never round, estimate, add, subtract or convert a number.
- Notes are quoted word for word in double quotes. Never guess a reason or a cause.
- For estimated items, say "about" and do not call the difference a gap.
- Mention, if present: restock items, exact items with a gap, container checks,
  menu items with no recipe yet, opening counts, closed days, and the day note.
- Plain English, one paragraph, at most 120 words. No headings, lists or markdown.
''';

// when groq answers with an error, or the answer has no text in it
class GroqException implements Exception {
  const GroqException(this.message);

  final String message;

  @override
  String toString() => 'GroqException: $message';
}

class GroqClient {
  GroqClient(this._http, this._apiKey);

  final http.Client _http;
  final String _apiKey;

  // sends the facts, gives back the model's text
  // throws GroqException on an error answer, or a network error (no internet) from http, or a timeout
  Future<String> summarize(String factsJson) async {
    final response = await _http
        .post(
          Uri.parse(groqUrl),
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': groqModel,
            // 0 = always the most likely words, the same facts give the same text
            'temperature': 0,
            'max_completion_tokens': groqMaxTokens,
            'messages': [
              {'role': 'system', 'content': groqInstructions},
              {'role': 'user', 'content': factsJson},
            ],
          }),
        )
        .timeout(groqTimeout);

    if (response.statusCode != 200) {
      // 401 = wrong key, 429 = too many calls, the body says more
      throw GroqException('HTTP ${response.statusCode}: ${response.body}');
    }

    // utf8 decode by hand, the body can have characters like – or “ in it
    // the text is at choices[0].message.content, each step is checked so a strange answer cant crash
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    Object? text;
    if (json is Map && json['choices'] is List) {
      final choices = json['choices'] as List;
      if (choices.isNotEmpty && choices.first is Map) {
        final message = (choices.first as Map)['message'];
        if (message is Map) text = message['content'];
      }
    }
    if (text is! String || text.trim().isEmpty) {
      throw const GroqException('The answer had no text');
    }
    return text.trim();
  }
}
