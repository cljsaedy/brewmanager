import 'package:sqflite/sqflite.dart';

import '../email/outbox_sender.dart';

// 1 email of the owner's reports tab, a daily report or a correction email from the outbox
class SentReport {
  const SentReport({
    required this.id,
    required this.kind,
    required this.businessDate,
    required this.subject,
    required this.html,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.sentAt,
  });

  final int id;
  // daily or correction
  final String kind;
  // the day the email is about, YYYY-MM-DD
  final String? businessDate;
  final String subject;
  // the email exactly as it was (or will be) sent
  final String html;
  final EmailStatus status;
  // how many times sending was tried
  final int attempts;
  // utc iso text
  final String createdAt;
  // utc iso text, null until it is sent
  final String? sentAt;

  bool get isDaily => kind == 'daily';
}

// reads the outbox for the owner's reports tab (feature 10)
// recovery emails are left out: they are not reports, and their body is blanked after sending (rule 11)
class SentReportsStore {
  SentReportsStore(this._db);

  final Database _db;

  // every daily and correction email, newest first
  Future<List<SentReport>> list() async {
    final rows = await _db.rawQuery('''
      SELECT outbox.*, business_days.business_date
      FROM outbox
      LEFT JOIN business_days ON business_days.id = outbox.day_id
      WHERE outbox.kind IN ('daily', 'correction')
      ORDER BY outbox.created_at DESC, outbox.id DESC
    ''');
    return [
      for (final row in rows)
        SentReport(
          id: row['id'] as int,
          kind: row['kind'] as String,
          businessDate: row['business_date'] as String?,
          subject: row['subject'] as String,
          html: row['html_body'] as String,
          status: OutboxSender.statusOf(row),
          attempts: row['attempts'] as int,
          createdAt: row['created_at'] as String,
          sentAt: row['sent_at'] as String?,
        ),
    ];
  }
}
