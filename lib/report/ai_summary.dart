import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/email_settings_store.dart';
import '../data/report_store.dart';
import '../security/key_store.dart';
import 'daily_email.dart';
import 'groq_client.dart';
import 'number_check.dart';
import 'report_facts.dart';
import 'template_summary.dart';

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

  // app_settings key of the last try in words, shown in owner settings
  // like "call failed: ClientException: Failed host lookup" so a failure says what went wrong
  static const String lastTryKey = EmailSettingsStore.lastAiTryKey;

  // longest error text kept, a groq error body can be long
  static const int _maxErrorLength = 300;

  // what went wrong on this try, null when nothing did
  String? _problem;

  // never throws, every problem just keeps the template
  // the outcome is saved on the day every time, whatever it is, and the last try is saved in words
  Future<SummaryOutcome> improve(int dayId) async {
    _problem = null;
    final outcome = await _attempt(dayId);
    try {
      await _db.update(
        'business_days',
        {'ai_outcome': outcome.dbValue},
        where: 'id = ?',
        whereArgs: [dayId],
      );
      await _db.insert('app_settings', {
        'key': lastTryKey,
        'value': _lastTryText(outcome),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // only the notes are lost, the email is fine
    }
    return outcome;
  }

  // like "check failed: did not match: 4" or "call failed: GroqException: HTTP 401: ..."
  String _lastTryText(SummaryOutcome outcome) {
    final words = outcome.dbValue.replaceAll('_', ' ');
    final problem = _problem;
    if (problem == null) return words;
    final short = problem.length > _maxErrorLength
        ? '${problem.substring(0, _maxErrorLength)}...'
        : problem;
    return '$words: $short';
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
      } catch (error) {
        // the error's text says what happened, like "Failed host lookup" = no internet
        _problem = error.toString();
        return SummaryOutcome.callFailed;
      }

      final check = checkNumbers(text, facts);
      if (!check.passed) {
        _problem = 'did not match: ${check.mismatches.join(', ')}';
        return SummaryOutcome.checkFailed;
      }

      // the email body and summary_source change together or not at all
      return await _db.transaction((txn) async {
        final changed = await txn.update(
          'outbox',
          {
            'html_body': dailyEmailHtml(
              report,
              summaryBullets(text),
              fromAi: true,
            ),
          },
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
    } catch (error) {
      // like secure storage not reading, the template stays and the day is fine
      _problem = error.toString();
      return SummaryOutcome.callFailed;
    }
  }
}
