import 'dart:convert';

import 'package:http/http.dart' as http;

// the groq chat api (openai style), called with the http package, no sdk (rule 10)
// docs: https://console.groq.com/docs/api-reference

const String groqUrl = 'https://api.groq.com/openai/v1/chat/completions';

// a current production model on groq, change it here if groq retires it
// check https://console.groq.com/docs/deprecations, the models page can be behind
// llama-3.3-70b-versatile was shut down on aug 16 2026, groq's replacement is this one
const String groqModel = 'openai/gpt-oss-120b';

// gpt-oss is a reasoning model, it thinks before it answers
// low = only a little thinking, putting given numbers into words doesnt need more, and it is faster
const String groqReasoningEffort = 'low';

// the longest the app waits for groq, after this the template summary is used
// 30 s since the answer is now 5 paragraphs, still short enough that submit doesnt feel stuck
const Duration groqTimeout = Duration(seconds: 30);

// the most the answer can be, the thinking counts toward it too
// no word limit for the summary itself (it writes what the day needs), this only stops a long day getting cut off halfway
const int groqMaxTokens = 2500;

// 0 = always the same words, higher = more natural but less the same each time
// 0.2 reads less stiff and the same day still gives about the same text, which helps the evaluation
// the number check guards the numbers whatever this is
const double groqTemperature = 0.2;

// the shape the answer must have, groq's strict structured outputs make the model follow it exactly
// docs: https://console.groq.com/docs/structured-outputs (gpt-oss-120b supports strict mode)
// strict needs every field in required and no extra fields
const Map<String, Object> summarySchema = {
  'type': 'object',
  'properties': {
    'overview': {'type': 'string'},
    'gaps': {'type': 'string'},
    'restock': {'type': 'string'},
    'containers': {'type': 'string'},
    'fine': {'type': 'string'},
  },
  'required': ['overview', 'gaps', 'restock', 'containers', 'fine'],
  'additionalProperties': false,
};

// what the model is told (rule 10)
// the app already picked what goes in each part and in what order, the model only puts it into words
// no thresholds: every gap and every finished container is in the facts, the owner judges them
const String groqInstructions = '''
You write the daily stock summary for the owner of a small cafe, like a manager
telling the owner what happened today.
The user message is JSON facts. The app already worked out every number and
already put every list in order.

Answer with JSON only, with these 5 fields. Each field is a short plain
paragraph, or an empty string when its list is empty:
- overview: what happened today: how many menu items were ordered, menu items
  ordered with no recipe yet, covered or closed days, opening counts and the
  day note if present.
- gaps: every item in "gaps", in the order given. For each say the item name
  first, what was used, what today's orders explain, and the gap. Example:
  Wings used 6 pcs, but based on today's orders 4 pcs should have been used,
  2 pcs more. If the item has a note, quote it and say it may explain part of
  it, for example: Staff noted "1 pck expired", which may explain part of it.
  If there is no note, say no note explains it.
- restock: every item in "restock", with what is left and the low level.
- containers: every item in "containers_finished": how much was finished and
  how much the orders since that date explain. Do not judge or compare them.
- fine: copy "closing_line" exactly (it may be empty).

Rules:
- Use only the facts given. Do not mention items that are not in these lists.
- Every number you write must be copied exactly from the facts, as digits
  (write 3, not three). Never write a number as a word. Never round, estimate,
  add, subtract or convert a number. Never work out a new number, for example
  never say how much a note does not explain.
- A note is never the cause. Never guess a reason.
- Say "orders" or "today's orders". Never use the word "tally".
- Plain sentences only. No markdown, no bullet points, no symbols like * or #.
- Write as much as the day needs and no more. Do not repeat every table row.
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
            'temperature': groqTemperature,
            'max_completion_tokens': groqMaxTokens,
            'reasoning_effort': groqReasoningEffort,
            // false = the thinking is left out of the answer, only message.content is used anyway
            'include_reasoning': false,
            // the answer must be json in the summary shape, see summarySchema
            'response_format': {
              'type': 'json_schema',
              'json_schema': {
                'name': 'daily_summary',
                'strict': true,
                'schema': summarySchema,
              },
            },
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
