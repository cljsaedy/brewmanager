import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/report_store.dart';
import '../security/key_store.dart';
import 'daily_email.dart';
import 'groq_client.dart';
import 'number_check.dart';
import 'report_facts.dart';

// what happened when the app tried the ai summary
// saved in business_days.ai_outcome so the evaluation can count passed vs fell back (chapter 4)
enum SummaryOutcome {
  // the ai text passed the number check and is in the email now
  ai('ai'),
  // no groq key saved, the template stays
  noKey('no_key'),
  // the call failed: no internet, timeout, wrong key, groq error
  callFailed('call_failed'),
  // the ai answered but a number didnt match the facts
  checkFailed('check_failed'),
  // the daily email was already sent, so it isnt changed anymore
  alreadySent('already_sent');

  const SummaryOutcome(this.dbValue);

  // the text saved in the db
  final String dbValue;
}

// tries to put the ai summary in a submitted day's daily email (rule 10)
// submit always queues the email with the template summary first, inside its transaction,
// so the day is never stuck waiting for the internet. this runs after that:
// if the ai text passes the number check it takes the template's place, if anything goes wrong the template stays
class AiSummary {
  AiSummary(this._db, this._keys, this._http);

  final Database _db;
  final KeyStore _keys;
  final http.Client _http;

  // never throws, every problem just keeps the template
  // the outcome is saved on the day every time, whatever it is
  Future<SummaryOutcome> improve(int dayId) async {
    final outcome = await _attempt(dayId);
    try {
      await _db.update(
        'business_days',
        {'ai_outcome': outcome.dbValue},
        where: 'id = ?',
        whereArgs: [dayId],
      );
    } catch (_) {
      // only the evaluation note is lost, the email is fine
    }
    return outcome;
  }

  Future<SummaryOutcome> _attempt(int dayId) async {
    try {
      final key = await _keys.read(ApiKey.groqKey);
      if (key == null || key.isEmpty) return SummaryOutcome.noKey;

      final report = await ReportStore(_db).load(dayId);
      final facts = jsonEncode(reportFacts(report));

      final String text;
      try {
        text = await GroqClient(_http, key).summarize(facts);
      } catch (_) {
        return SummaryOutcome.callFailed;
      }

      if (!checkNumbers(text, facts).passed) return SummaryOutcome.checkFailed;

      // the email body and summary_source change together or not at all
      return await _db.transaction((txn) async {
        final changed = await txn.update(
          'outbox',
          {'html_body': dailyEmailHtml(report, text)},
          where: "kind = 'daily' AND day_id = ? AND status = 'queued'",
          whereArgs: [dayId],
        );
        if (changed == 0) return SummaryOutcome.alreadySent;

        await txn.update(
          'business_days',
          {'summary_source': 'ai'},
          where: 'id = ?',
          whereArgs: [dayId],
        );
        return SummaryOutcome.ai;
      });
    } catch (_) {
      // like secure storage not reading, the template stays and the day is fine
      return SummaryOutcome.callFailed;
    }
  }
}
