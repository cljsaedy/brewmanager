import 'dart:convert';

import 'package:http/http.dart' as http;

// the mailjet send api v3.1, called with the http package, no sdk (rule 10)
// docs: https://dev.mailjet.com/email/guides/send-api-v31/

const String mailjetUrl = 'https://api.mailjet.com/v3.1/send';

// the longest the app waits for 1 email, after this it counts as no internet and tries again later
const Duration mailjetTimeout = Duration(seconds: 20);

// the name the owner sees as the sender, next to the sender email
const String senderName = 'BrewManager';

// mailjet answered but didnt send, like a wrong key (401) or a sender email that isnt verified
// the message is mailjet's own answer so the owner can see why
class MailjetException implements Exception {
  const MailjetException(this.message);

  final String message;

  @override
  String toString() => 'MailjetException: $message';
}

class MailjetClient {
  MailjetClient(this._http, this._apiKey, this._secretKey);

  final http.Client _http;
  final String _apiKey;
  final String _secretKey;

  // sends 1 html email
  // throws MailjetException when mailjet says no
  // a network error (no internet) or a timeout comes out as the http error or a TimeoutException
  Future<void> send({
    required String from,
    required String to,
    required String subject,
    required String html,
  }) async {
    // basic auth = "key:secret" in base64, mailjet's docs use the api key and secret as user and password
    final login = base64Encode(utf8.encode('$_apiKey:$_secretKey'));

    final response = await _http
        .post(
          Uri.parse(mailjetUrl),
          headers: {
            'Authorization': 'Basic $login',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'Messages': [
              {
                'From': {'Email': from, 'Name': senderName},
                'To': [
                  {'Email': to},
                ],
                'Subject': subject,
                'HTMLPart': html,
              },
            ],
          }),
        )
        .timeout(mailjetTimeout);

    // only a 200 where every message says "success" counts as sent, anything else is mailjet saying no
    final body = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200 || !_allSent(body)) {
      throw MailjetException('HTTP ${response.statusCode}: $body');
    }
  }

  // true when the answer has Messages and each one has Status "success"
  bool _allSent(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map || json['Messages'] is! List) return false;
      final messages = json['Messages'] as List;
      return messages.isNotEmpty &&
          messages.every(
            (message) => message is Map && message['Status'] == 'success',
          );
    } on FormatException {
      // not json at all
      return false;
    }
  }
}
