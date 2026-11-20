// test/sms_parser_test.dart
// Ported from sms-transaction-parser jvmTest (KenyaRegistryRoutingTest,
// FallbackMatcherTest, MessageDateParserTest) to verify the Dart port.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:finwick/domain/sms_import/sms_parser.dart';

final _ts = DateTime.utc(2026, 8, 15, 14, 30);

late TemplateRegistry registry;

String _mpesaSendJson(
        {int revision = 1,
        String serviceName = 'M-Pesa Send Money',
        bool active = true}) =>
    '''
{
  "id": "mpesa_send",
  "senderId": "MPESA",
  "serviceName": "$serviceName",
  "anchors": [{ "textBefore": "Confirmed. Ksh", "textAfter": " sent to" }],
  "fields": [
    { "name": "REFERENCE", "anchor": { "textBefore": "", "textAfter": " Confirmed." }, "type": "TEXT" },
    { "name": "AMOUNT", "anchor": { "textBefore": "Ksh", "textAfter": " sent to" }, "type": "CURRENCY" },
    { "name": "MERCHANT", "anchor": { "textBefore": "sent to ", "textAfter": " on " }, "type": "TEXT" },
    { "name": "BALANCE", "anchor": { "textBefore": "New M-PESA balance is Ksh", "textAfter": ". " }, "type": "CURRENCY" },
    { "name": "FEE", "anchor": { "textBefore": "Transaction cost, Ksh", "textAfter": "." }, "type": "CURRENCY" }
  ],
  "transactionDirection": "EXPENSE",
  "revision": $revision,
  "isBuiltIn": true,
  "isActive": $active
}
''';

void main() {
  setUpAll(() {
    final dir = Directory('assets/sms_templates/kenya');
    final index =
        jsonDecode(File('${dir.path}/index.json').readAsStringSync()) as List;
    final texts =
        index.map((f) => File('${dir.path}/$f').readAsStringSync()).toList();
    registry = TemplateRegistry.fromTemplateJson(texts);
  });

  group('Kenya registry routing', () {
    test('routing precedence follows index order inside one sender', () async {
      final sendBody =
          'FIXTURE03 Confirmed. Ksh1,500.00 sent to JOHN DOE EXAMPLE 0749000001 on 15/8/26 at 2:30 PM. New M-PESA balance is Ksh8,500.00. Transaction cost, Ksh57.00.';
      final r1 = await registry.parse('MPESA', sendBody, _ts);
      expect(r1, isA<ParseSuccess>());
      expect((r1 as ParseSuccess).templateId, 'mpesa_send');

      final payBillBody =
          'FIXTURE02 Confirmed. Ksh2,400.00 sent to KPLC 777777 for account 12345678 on 15/8/26 at 3:00 PM. New M-PESA balance is Ksh7,600.00. Transaction cost, Ksh33.00.';
      final r2 = await registry.parse('MPESA', payBillBody, _ts);
      expect((r2 as ParseSuccess).templateId, 'mpesa_pay_bill');

      final airtimeBody =
          'PT8N4W7Q2K confirmed.You bought Ksh200.00 of airtime on 31/10/25 at 2:01 PM.New M-PESA balance is Ksh77,777.77. Transaction cost, Ksh0.00.';
      final r3 = await registry.parse('MPESA', airtimeBody, _ts);
      expect((r3 as ParseSuccess).templateId, 'mpesa_airtime');
    });

    test('unknown sender with a transaction-shaped message falls back',
        () async {
      final body =
          'KES 1,200.00 sent to JOHN DOE EXAMPLE 0749000001 on 15/8/26. Confirmed.';
      final r = await registry.parse('EQUITYBANK', body, _ts);
      expect(r, isA<ParseSuccess>());
      final s = r as ParseSuccess;
      expect(s.templateId, isNull);
      expect(s.transaction.amountMinorUnits, 120000);
      expect(s.transaction.currency, 'KES');
      expect(s.transaction.type, TransactionType.expense);
    });

    test('unknown sender with noise is not routed', () async {
      final r = await registry.parse(
          'PROMO', 'Your OTP is 9012. Do not share it with anyone.', _ts);
      expect(r, isA<ParseFailure>());
      expect((r as ParseFailure).reason, ParseFailureReason.noRoute);
    });

    test('unknown sender with a transaction shape but no amount is a no-match',
        () async {
      final r = await registry.parse('EQUITYBANK',
          'Transaction confirmed for your account. Thank you.', _ts);
      expect(r, isA<ParseFailure>());
      final f = r as ParseFailure;
      expect(f.reason, ParseFailureReason.noMatch);
      expect(f.detail, 'no amount');
    });

    test('incomplete routed shape is returned instead of falling back',
        () async {
      const templateJson = '''
        {
          "id": "test_incomplete",
          "senderId": "TESTBANK",
          "serviceName": "Test Incomplete",
          "anchors": [{ "textBefore": "Payment of ", "textAfter": " received" }],
          "fields": [
            { "name": "AMOUNT", "anchor": { "textBefore": "", "textAfter": " received" }, "type": "CURRENCY" }
          ],
          "transactionDirection": "EXPENSE",
          "revision": 1,
          "isBuiltIn": true,
          "isActive": true
        }
        ''';
      final reg = TemplateRegistry.fromTemplateJson([templateJson]);
      final r = await reg.parse(
          'TESTBANK', 'Payment of X received today, thank you.', _ts);
      expect(r, isA<ParseFailure>());
      final f = r as ParseFailure;
      expect(f.reason, ParseFailureReason.incomplete);
      expect(f.detail, 'missing amount');
    });

    test('same id with a higher revision replaces the built-in', () {
      final builtIn = _mpesaSendJson(revision: 1);
      final override =
          _mpesaSendJson(revision: 2, serviceName: 'M-Pesa Send Money v2');
      expect(
          TemplateRegistry.fromTemplateJson([builtIn, override])
              .templates
              .single
              .serviceName,
          'M-Pesa Send Money v2');
      expect(
          TemplateRegistry.fromTemplateJson([override, builtIn])
              .templates
              .single
              .serviceName,
          'M-Pesa Send Money v2');
    });

    test('same id with a lower revision is ignored', () {
      final builtIn =
          _mpesaSendJson(revision: 2, serviceName: 'M-Pesa Send Money v2');
      final stale = _mpesaSendJson(revision: 1);
      expect(
          TemplateRegistry.fromTemplateJson([builtIn, stale])
              .templates
              .single
              .serviceName,
          'M-Pesa Send Money v2');
    });

    test('inactive templates are excluded from routing', () async {
      final inactive = _mpesaSendJson(active: false);
      final reg = TemplateRegistry.fromTemplateJson([inactive]);
      expect(reg.templates, isEmpty);
      final r = await reg.parse(
          'MPESA', 'Your OTP is 9012. Do not share it with anyone.', _ts);
      expect((r as ParseFailure).reason, ParseFailureReason.noRoute);
    });

    test('an inactive highest revision deactivates the id', () {
      final builtIn = _mpesaSendJson(revision: 1, active: true);
      final retired = _mpesaSendJson(
          revision: 2, serviceName: 'M-Pesa Send Money v2', active: false);
      expect(TemplateRegistry.fromTemplateJson([builtIn, retired]).templates,
          isEmpty);
    });

    test('fallback disabled turns un-routed messages into no-route', () async {
      final reg = TemplateRegistry(registry.templates, fallbackEnabled: false);
      final transactional =
          'KES 1,200.00 sent to JOHN DOE EXAMPLE 0749000001 on 15/8/26. Confirmed.';
      expect(
          (await reg.parse('EQUITYBANK', transactional, _ts) as ParseFailure)
              .reason,
          ParseFailureReason.noRoute);
      expect(
          (await reg.parse('MPESA', 'Your OTP is 9012. Do not share it.', _ts)
                  as ParseFailure)
              .reason,
          ParseFailureReason.noRoute);
    });

    test(
        'fromTemplateJson round-trips a built-in template into a working registry',
        () async {
      final reg = TemplateRegistry.fromTemplateJson([_mpesaSendJson()]);
      final r = await reg.parse(
          'MPESA',
          'FIXTURE01 Confirmed. Ksh1,500.00 sent to JOHN DOE EXAMPLE 0749000001 on 15/8/26 at 2:30 PM. New M-PESA balance is Ksh8,500.00. Transaction cost, Ksh57.00.',
          _ts);
      final s = r as ParseSuccess;
      expect(s.templateId, 'mpesa_send');
      expect(s.transaction.amountMinorUnits, 150000);
      expect(s.transaction.feeMinorUnits, 5700);
    });

    test(
        'preferMonthFirst resolves month-first template dates day-first cannot read',
        () async {
      final dayFirst = await registry.parse(
          'MPESA',
          'PT8N4W7Q2K confirmed.You bought Ksh200.00 of airtime on 31/10/25 at 2:01 PM.New M-PESA balance is Ksh77,777.77. Transaction cost, Ksh0.00.',
          _ts);
      expect(
          (dayFirst as ParseSuccess)
              .transaction
              .timestamp
              .millisecondsSinceEpoch,
          1761868800000);

      final monthFirstBody =
          'PT8N4W7Q2K confirmed.You bought Ksh200.00 of airtime on 10/31/2025 at 2:01 PM.New M-PESA balance is Ksh77,777.77. Transaction cost, Ksh0.00.';
      final withoutPreference =
          await registry.parse('MPESA', monthFirstBody, _ts);
      expect(
          (withoutPreference as ParseSuccess)
              .transaction
              .timestamp
              .millisecondsSinceEpoch,
          1786804200000);

      final withPreference = await registry.parse('MPESA', monthFirstBody, _ts,
          preferMonthFirst: true);
      expect(
          (withPreference as ParseSuccess)
              .transaction
              .timestamp
              .millisecondsSinceEpoch,
          1761868800000);
    });

    test('fallback success carries a raw hash of the original body', () async {
      final body =
          'FIXTURE34 Confirmed.\nKsh1,500.00 sent to JOHN DOE EXAMPLE 0749000001\non 15/8/26 at 2:30 PM.\nNew M-PESA balance is Ksh8,500.00. Transaction cost, Ksh57.00.';
      final r = await registry.parse('MPESA', body, _ts);
      final tx = (r as ParseSuccess).transaction;
      expect(tx.rawHash, await sha256Hex('MPESA:$body'));
    });

    test('normalizeSenderId uppercases and strips non-alphanumerics', () {
      expect(normalizeSenderId('M-PESA'), 'MPESA');
      expect(normalizeSenderId(' mpesa '), 'MPESA');
      expect(normalizeSenderId('Stan Chart'), 'STANCHART');
      expect(normalizeSenderId('Equity.Bank'), 'EQUITYBANK');
      expect(
          normalizeSenderId('M_PESA 99').replaceAll(RegExp(r'[^A-Z0-9]'), ''),
          normalizeSenderId('M_PESA 99'));
    });
  });

  group('Fallback matcher', () {
    test('credit card due notices are not booked as expenses', () async {
      final r = await registry.parse(
        'NABIL_ALERT',
        'Your Card XXXX1246 payment is due on 09-NOV-26. Total and min amounts due are Amt NPR 9489.88 and Amt NPR 9489.88 respectively.',
        _ts,
        defaultCurrency: 'NPR',
      );
      expect(r, isA<ParseFailure>());
    });

    test('NT rupee deductions parse as expenses', () async {
      final r = await registry.parse(
        '1415',
        'GSM Data Pack_11GB_30days has been activated successfully on 9840361144,329.00Rupees has been deducted from balance. Offer is valid till 2026/12/13.',
        _ts,
        defaultCurrency: 'NPR',
      );
      expect(r, isA<ParseSuccess>());
      final s = r as ParseSuccess;
      expect(s.transaction.type, TransactionType.expense);
      expect(s.transaction.amountMinorUnits, 32900);
    });

    test('CIT retirement credit stays low-confidence for review', () async {
      final r = await registry.parse(
        'CIT_Alert',
        "Dear sir/ma'am Your CIT No ****** OF KBB has been CR Rs 10000.00.",
        _ts,
        defaultCurrency: 'NPR',
      );
      expect(r, isA<ParseSuccess>());
      final s = r as ParseSuccess;
      expect(s.transaction.type, TransactionType.income);
      expect(s.transaction.confidence, ParseConfidence.low);
      expect(s.transaction.reviewReason, 'investment');
    });

    test('fund transfer shape parses as transfer for verification', () async {
      final r = await registry.parse(
        'SBL_Alert',
        'Dear MAUSAM, AC ###505652256, NPR 315.25 withdrawn on 11/10/2026 for Fund Trf to NABIL BANK LTD.',
        _ts,
        defaultCurrency: 'NPR',
      );
      expect(r, isA<ParseSuccess>());
      final s = r as ParseSuccess;
      expect(s.transaction.type, TransactionType.transfer);
    });
    test('labeled amount without a token is not declared', () async {
      final body =
          'Acct: 0123456789\nAmt: 2,500.00\nDesc: MARKET PURCHASE\nDate: 15/08/2026\nDebit: 2,500.00';
      final r = await registry.parse('FOREIGNBANK', body, _ts,
          defaultCurrency: 'KES');
      expect(r, isA<ParseSuccess>());
      final t = (r as ParseSuccess).transaction;
      expect(t.amountMinorUnits, 250000);
      expect(t.currency, 'KES');
      expect(t.currencyDeclared, isFalse);
    });

    test('labeled amount with a token is declared', () async {
      final body =
          'Acct: 0123456789\nAmt: NGN 2,500.00\nDesc: MARKET PURCHASE\nDate: 15/08/2026\nDebit: NGN 2,500.00';
      final r = await registry.parse('FOREIGNBANK', body, _ts,
          defaultCurrency: 'KES');
      expect(r, isA<ParseSuccess>());
      final t = (r as ParseSuccess).transaction;
      expect(t.amountMinorUnits, 250000);
      expect(t.currency, 'NGN');
      expect(t.currencyDeclared, isTrue);
    });

    test('debit line label directs expense', () async {
      final body =
          'Transaction Alert\nDesc: POS PURCHASE LAGOS\nDebit: 57,000.00\nDate: 2026-01-20';
      final r = await registry.parse('FOREIGNBANK', body, _ts,
          defaultCurrency: 'NGN');
      expect(r, isA<ParseSuccess>());
      final t = (r as ParseSuccess).transaction;
      expect(t.type, TransactionType.expense);
      expect(t.amountMinorUnits, 5700000);
    });

    test('credit line label directs income', () async {
      final body =
          'Transaction Alert\nDesc: TRANSFER FROM A. OKORO\nCredit: 125,000.00\nDate: 2026-01-20';
      final r = await registry.parse('FOREIGNBANK', body, _ts,
          defaultCurrency: 'NGN');
      expect(r, isA<ParseSuccess>());
      final t = (r as ParseSuccess).transaction;
      expect(t.type, TransactionType.income);
      expect(t.amountMinorUnits, 12500000);
    });

    test('bare amount without currency token is not trusted in free text',
        () async {
      final r = await registry.parse(
          'BANKALERT', 'You paid 500 for lunch today.', _ts);
      // No currency token in free text -> no amount -> no match.
      expect(r, isA<ParseFailure>());
    });

    test('payment received by provider is not booked as income', () async {
      final body =
          'Payment of Ksh 1,000.00 for your Safaricom Home Fibre Account 11900864 has been received.';
      final r = await registry.parse('SAFARICOM', body, _ts);
      if (r is ParseSuccess) {
        expect(r.transaction.type, isNot(TransactionType.income));
      }
    });
  });

  group('Message date parser', () {
    test('dmy4 and dmy2 shapes', () {
      expect(MessageDateParser.parseTemplateDate('15/08/2026'),
          DateTime.utc(2026, 8, 15));
      expect(MessageDateParser.parseTemplateDate('15/08/26'),
          DateTime.utc(2026, 8, 15));
    });

    test('textual and ISO shapes', () {
      expect(MessageDateParser.parseTemplateDate('15 Aug 2026'),
          DateTime.utc(2026, 8, 15));
      expect(MessageDateParser.parseTemplateDate('2026-08-15'),
          DateTime.utc(2026, 8, 15));
    });

    test('flexible date with trailing 12-hour time', () {
      final d = MessageDateParser.parseFlexibleDate(
          'on Mar 17, 2026 at 1:56 PM ET', true);
      expect(d, DateTime.utc(2026, 3, 17, 13, 56));
    });

    test('preferMonthFirst flips ambiguous numeric dates', () {
      expect(
          MessageDateParser.parseFlexibleDate('on 05/03/2026', false)!.day, 5);
      expect(
          MessageDateParser.parseFlexibleDate('on 05/03/2026', true)!.month, 5);
      // A first component above 12 can only be the day.
      expect(
          MessageDateParser.parseFlexibleDate('on 25/03/2026', true)!.day, 25);
    });
  });
}
