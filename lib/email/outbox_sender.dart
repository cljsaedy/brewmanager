import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/email_settings_store.dart';
import '../logic/clock.dart';
import '../security/key_store.dart';
import 'mailjet_client.dart';

// what the screens show for 1 email (rule 10)
enum EmailState {
  // mailjet took it
  sent,
  // not sent yet: no internet, or the emails / mailjet keys are not set
  waiting,
  // mailjet said no, the error says why
  failed,
}

class EmailStatus {
  const EmailStatus(this.state, {this.error, this.needsSettings = false});

  final EmailState state;
  // the saved error text, null when there is none
  final String? error;
  // waiting only because the owner email, sender email or mailjet keys are not set
  final bool needsSettings;
}

// sends what is in the outbox (rule 10)
// every email goes in the outbox first (submit, correction, new pin), this sends them
// it runs when the app starts and after each submit, and later from resend in reports (feature 10)
//
// for each email, oldest first:
// - sent: status sent, a recovery email gets its body blanked so the plain code never stays in the db or backups
// - no internet or timeout: stays queued (waiting), and the run stops since the rest cant go out either
// - mailjet says no: status failed with mailjet's answer, it is tried again next time in case settings got fixed
class OutboxSender {
  OutboxSender(this._db, this._keys, this._http, {Clock clock = utcNow})
    : _clock = clock;

  final Database _db;
  final KeyStore _keys;
  final http.Client _http;
  final Clock _clock;

  // saved as last_error when the emails or keys are missing, the status screens look for it
  static const String notSetError =
      'Not sent: set the owner email, sender email and Mailjet keys in owner Settings.';

  // longest error kept, a mailjet answer can be long
  static const int _maxErrorLength = 500;

  // the last run of each database, a new run waits for it
  // so an app start and a submit at the same time cant send an email twice
  // Expando = a map that hangs a value on an object (here the db) without changing it
  // 1 lock per db: the app has 1 db so it is 1 lock, and each test has its own db so tests cant block each other
  static final Expando<Future<void>> _lastRuns = Expando();

  // sends everything waiting, never throws
  Future<void> sendAll() {
    final last = _lastRuns[_db] ?? Future<void>.value();
    final run = last.then((_) => _sendAllNow());
    _lastRuns[_db] = run;
    return run;
  }

  Future<void> _sendAllNow() async {
    try {
      final rows = await _db.query(
        'outbox',
        where: "status IN ('queued', 'failed')",
        orderBy: 'id',
      );
      if (rows.isEmpty) return;

      final settings = EmailSettingsStore(_db, _keys);
      final loaded = await settings.load();
      final apiKey = await settings.key(ApiKey.mailjetKey);
      final secretKey = await settings.key(ApiKey.mailjetSecret);
      final owner = loaded.ownerEmail;
      final sender = loaded.senderEmail;
      if (owner == null ||
          sender == null ||
          apiKey == null ||
          secretKey == null) {
        // nothing can go out, say why on the ones still waiting
        await _db.update('outbox', {
          'last_error': notSetError,
        }, where: "status = 'queued'");
        return;
      }

      final client = MailjetClient(_http, apiKey, secretKey);
      for (final row in rows) {
        final keepGoing = await _sendOne(client, row, from: sender, to: owner);
        if (!keepGoing) return;
      }
    } catch (_) {
      // like secure storage not reading or the db closing, the emails stay and get tried next time
    }
  }

  // gives back false when the run should stop (no internet)
  Future<bool> _sendOne(
    MailjetClient client,
    Map<String, Object?> row, {
    required String from,
    required String to,
  }) async {
    final id = row['id'] as int;
    final attempts = (row['attempts'] as int) + 1;

    try {
      await client.send(
        from: from,
        to: to,
        subject: row['subject'] as String,
        html: row['html_body'] as String,
      );
    } on MailjetException catch (error) {
      await _save(id, {
        'status': 'failed',
        'attempts': attempts,
        'last_error': _short(error.message),
      });
      return true;
    } catch (error) {
      // anything else is the connection: no internet, a failed host lookup, a timeout
      if (error is http.ClientException ||
          error is SocketException ||
          error is TimeoutException) {
        await _save(id, {
          'status': 'queued',
          'attempts': attempts,
          'last_error': _short('No internet: $error'),
        });
        return false;
      }
      await _save(id, {
        'status': 'failed',
        'attempts': attempts,
        'last_error': _short(error.toString()),
      });
      return true;
    }

    await _save(id, {
      'status': 'sent',
      'attempts': attempts,
      'last_error': null,
      'sent_at': _clock().toIso8601String(),
      // the recovery code must not stay in the db (rule 11), html_body cant be null so it becomes empty
      if (row['kind'] == 'recovery') 'html_body': '',
    });
    return true;
  }

  Future<void> _save(int id, Map<String, Object?> values) {
    return _db.update('outbox', values, where: 'id = ?', whereArgs: [id]);
  }

  String _short(String text) {
    return text.length > _maxErrorLength
        ? '${text.substring(0, _maxErrorLength)}...'
        : text;
  }

  // the status of a day's daily email, for the submitted screen
  // null = there is none (should not happen after a submit)
  Future<EmailStatus?> dailyStatus(int dayId) async {
    final rows = await _db.query(
      'outbox',
      where: "kind = 'daily' AND day_id = ?",
      whereArgs: [dayId],
    );
    if (rows.isEmpty) return null;
    return statusOf(rows.first);
  }

  // turns an outbox row into what screens show
  static EmailStatus statusOf(Map<String, Object?> row) {
    final error = row['last_error'] as String?;
    return switch (row['status']) {
      'sent' => const EmailStatus(EmailState.sent),
      'failed' => EmailStatus(EmailState.failed, error: error),
      _ => EmailStatus(
        EmailState.waiting,
        error: error,
        needsSettings: error == notSetError,
      ),
    };
  }
}
