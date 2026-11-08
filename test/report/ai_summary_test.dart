import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:brewmanager/data/count_store.dart';
import 'package:brewmanager/data/menu_item.dart';
import 'package:brewmanager/data/menu_item_store.dart';
import 'package:brewmanager/data/recipe_store.dart';
import 'package:brewmanager/data/stock_item.dart';
import 'package:brewmanager/data/stock_item_store.dart';
import 'package:brewmanager/logic/units.dart';
import 'package:brewmanager/report/ai_summary.dart';
import 'package:brewmanager/security/key_store.dart';

import '../helpers/test_database.dart';

// low at 5 packs
const StockItem friesPack = StockItem(
  name: 'Fries pack',
  category: 'Food',
  baseUnit: BaseUnit.pcs,
  countType: CountType.number,
  containerLabel: 'pack',
  lowMode: LowMode.exact,
  lowValue: 5,
);

// nov 1: opening count of 8 fries
// nov 2: 5 left, 2 french fries tallied: used 3, expected 2, gap 1, restock (5 is at the low level)
const String goodText =
    'On Mon, Nov 2, 2 menu items were tallied. Fries pack used 3 packs '
    'against 2 expected, a gap of 1 pack, and is down to 5 packs, so a '
    'restock is recommended.';

void main() {
  late Database db;
  late MemoryKeyStore keys;
  late int dayId;
  // what the fake groq got, null = it was never called
  String? sentBody;

  setUp(() async {
    db = await openTestDatabase();
    keys = MemoryKeyStore()..values[ApiKey.groqKey] = 'test-key';
    sentBody = null;
    var now = DateTime.utc(2026, 11, 1, 10);
    final counts = CountStore(db, clock: () => now);

    final friesId = await StockItemStore(db).add(friesPack);
    // a price hint, it must never be sent to the ai
    final menuId = await MenuItemStore(db, clock: () => now).add(
      const MenuItem(name: 'French Fries', category: 'Food', priceHint: 987),
    );
    await RecipeStore(db, clock: () => now).addLine(menuId, friesId, 1);

    var day = await counts.loadDraft();
    await counts.saveNumberCount(day.rows.single.line.id, 8);
    await counts.submits.submit(day.day.id, date: '2026-11-01');
    now = DateTime.utc(2026, 11, 2, 10);

    day = await counts.loadDraft();
    await counts.saveNumberCount(day.rows.single.line.id, 5);
    await counts.tally.add(day.day.id, menuId);
    await counts.tally.add(day.day.id, menuId);
    await counts.submits.submit(day.day.id, date: '2026-11-02');
    dayId = day.day.id;
  });

  tearDown(() async {
    await db.close();
  });

  // a fake groq that always answers with this text
  http.Client groqSays(String text) {
    return MockClient((request) async {
      sentBody = request.body;
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {'content': text},
              },
            ],
          }),
        ),
        200,
      );
    });
  }

  Future<String> emailBody() async {
    final rows = await db.query(
      'outbox',
      where: "kind = 'daily' AND day_id = ?",
      whereArgs: [dayId],
    );
    return rows.single['html_body'] as String;
  }

  Future<String?> source() async {
    final rows = await db.query(
      'business_days',
      where: 'id = ?',
      whereArgs: [dayId],
    );
    return rows.single['summary_source'] as String?;
  }

  Future<String?> savedOutcome() async {
    final rows = await db.query(
      'business_days',
      where: 'id = ?',
      whereArgs: [dayId],
    );
    return rows.single['ai_outcome'] as String?;
  }

  test('every outcome is saved on the day for the evaluation', () async {
    expect(await savedOutcome(), isNull);

    final cases = <http.Client, String>{
      groqSays('Fries pack used 4 packs.'): 'check_failed',
      MockClient((_) async => http.Response('busy', 429)): 'call_failed',
      groqSays(goodText): 'ai',
    };
    for (final entry in cases.entries) {
      await AiSummary(db, keys, entry.key).improve(dayId);
      expect(await savedOutcome(), entry.value);
    }

    // the email is sent now, so a later try cant change it
    await db.update('outbox', {'status': 'sent'});
    await AiSummary(db, keys, groqSays(goodText)).improve(dayId);
    expect(await savedOutcome(), 'already_sent');

    keys.values.clear();
    await AiSummary(db, keys, groqSays(goodText)).improve(dayId);
    expect(await savedOutcome(), 'no_key');
  });

  test('a text that passes goes in the email', () async {
    final outcome = await AiSummary(
      db,
      keys,
      groqSays(goodText),
    ).improve(dayId);

    expect(outcome, SummaryOutcome.ai);
    expect(await emailBody(), contains('a gap of 1 pack'));
    expect(
      await emailBody(),
      isNot(contains('menu items were tallied. Restock')),
    );
    expect(await source(), 'ai');
  });

  test('a wrong number keeps the template', () async {
    final outcome = await AiSummary(
      db,
      keys,
      groqSays('Fries pack used 4 packs.'),
    ).improve(dayId);

    expect(outcome, SummaryOutcome.checkFailed);
    expect(await emailBody(), contains('2 menu items were tallied.'));
    expect(await source(), 'template');
  });

  test('a number word keeps the template', () async {
    final outcome = await AiSummary(
      db,
      keys,
      groqSays('Fries pack used three packs, two were expected.'),
    ).improve(dayId);

    expect(outcome, SummaryOutcome.checkFailed);
    expect(await source(), 'template');
  });

  test('no key: groq is never called', () async {
    keys.values.clear();

    final outcome = await AiSummary(
      db,
      keys,
      groqSays(goodText),
    ).improve(dayId);

    expect(outcome, SummaryOutcome.noKey);
    expect(sentBody, isNull);
    expect(await source(), 'template');
  });

  test('no internet keeps the template', () async {
    final offline = MockClient(
      (_) async => throw http.ClientException('Failed host lookup'),
    );

    final outcome = await AiSummary(db, keys, offline).improve(dayId);

    expect(outcome, SummaryOutcome.callFailed);
    expect(await source(), 'template');
  });

  test('a groq error keeps the template', () async {
    final failing = MockClient((_) async => http.Response('busy', 429));

    expect(
      await AiSummary(db, keys, failing).improve(dayId),
      SummaryOutcome.callFailed,
    );
  });

  test('an email that was already sent is not changed', () async {
    await db.update(
      'outbox',
      {'status': 'sent'},
      where: "kind = 'daily' AND day_id = ?",
      whereArgs: [dayId],
    );

    final outcome = await AiSummary(
      db,
      keys,
      groqSays(goodText),
    ).improve(dayId);

    expect(outcome, SummaryOutcome.alreadySent);
    expect(await source(), 'template');
  });

  test('the facts have the numbers and no price', () async {
    await AiSummary(db, keys, groqSays(goodText)).improve(dayId);

    final body = jsonDecode(sentBody!) as Map<String, dynamic>;
    final facts = jsonDecode(body['messages'][1]['content'] as String);
    expect(facts['menu_items_tallied'], 2);
    expect(facts['exact_items'], [
      {
        'item': 'Fries pack',
        'used': 3,
        'expected': 2,
        'gap': 1,
        'unit': 'packs',
      },
    ]);
    expect(sentBody, isNot(contains('987')));
    expect(sentBody!.toLowerCase(), isNot(contains('price')));
  });
}
