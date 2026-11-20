// Regression tests for real-world Nepalese bank / payment SMS shapes
// (Laxmi Bank, NBL, SSF, CIT, generic banks, eSewa/KHALTI/FONEPAY).
//
// These messages have no dedicated sender template (the built-in pack is
// Kenya-only), so they must be recovered by the sender-agnostic fallback
// tier. The assertions pin the type, amount, currency, merchant, and date
// the fallback produces, guarding the gate / amount / date / merchant fixes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:finwick/domain/sms_import/sms_parser.dart';

final _ts = DateTime.utc(2026, 8, 15, 14, 30);

late TemplateRegistry registry;

DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);

/// One expected parse outcome. [merchant] null means "no merchant extracted";
/// [date] is the exact timestamp the parser should produce.
class _Case {
  final String body;
  final TransactionType type;
  final int minor;
  final String? merchant;
  final DateTime date;
  const _Case(this.body, this.type, this.minor, this.merchant, this.date);
}

final _cases = <_Case>[
  // ---- Laxmi Bank -------------------------------------------------------
  _Case(
    'Dear Customer, Your ###5175 has been credited by NPR 2,000.00 on 05/01/2023 21:33:19. Remarks:cIPS/ACCOUNTFT:Aditi Khan. Laxmi Bank',
    TransactionType.income,
    200000,
    'cIPS/ACCOUNTFT:Aditi Khan',
    _d(2023, 1, 5),
  ),
  _Case(
    'Dear Customer, Your #40035175 has been credited by NPR 5,000.00 on 06/10/24. Remarks:FON:IBFT:571197151:3725:LXBLNPKA:NARBNPKA:JANUKA K -Laxmi Sunrise',
    TransactionType.income,
    500000,
    'FON:IBFT:571197151:3725:LXBLNPKA:NARBNPKA:JANUKA K',
    _d(2024, 10, 6), // 2-digit year -> 2000 + 24
  ),
  _Case(
    'Dear Customer, Your ###5175 has been debited by NPR 4,000.00 on 21/02/2022 09:35:28. Remarks:CASH WITHDRAWAL FROM ATM-. Laxmi Bank',
    TransactionType.expense,
    400000,
    'CASH WITHDRAWAL FROM ATM',
    _d(2022, 2, 21),
  ),
  _Case(
    'Dear Customer, Your ###5175 has been debited by NPR 3,000.00 on 08/03/2022 11:15:52. Remarks:ATM CASH WITH DRAWN FROM. Laxmi Bank',
    TransactionType.expense,
    300000,
    'ATM CASH WITH DRAWN FROM',
    _d(2022, 3, 8),
  ),
  // ---- NBL --------------------------------------------------------------
  _Case(
    'Dear MAUSAM,##001 credited NPR 30,000.00 02/05/2023 11:28,050123043000S00L MINADEVI ADHIKARI.  NBL',
    TransactionType.income,
    3000000,
    '050123043000S00L MINADEVI ADHIKARI',
    _d(2023, 5, 2),
  ),
  _Case(
    'Dear MAUSAM,##001 debited NPR 500.00 30/10/2023 16:48,9840361144 IMEPAY:9840361144.  NBL',
    TransactionType.expense,
    50000,
    '9840361144 IMEPAY:9840361144',
    _d(2023, 10, 30),
  ),
  _Case(
    'Dear MAUSAM,##001 debited NPR 3,000.00 25/03/2022 10:14,4089271960003583@.  NBL',
    TransactionType.expense,
    300000,
    '4089271960003583@',
    _d(2022, 3, 25),
  ),
  _Case(
    'Dear MAUSAM,##001 credited NPR 14,000.00 25/03/2022 10:36,SELF CASH.  NBL',
    TransactionType.income,
    1400000,
    'SELF CASH',
    _d(2022, 3, 25),
  ),
  // ---- Generic bank -----------------------------------------------------
  _Case(
    'Your a/c ##533 is Credited By NPR 3,010.00 on 18/12/2021 by:IPS. Download Mobile Banking bit.ly/2TYvnhB.',
    TransactionType.income,
    301000,
    'IPS',
    _d(2021, 12, 18),
  ),
  _Case(
    'Your a/c ##533 is Debited By NPR 25,400.00 on 20/01/2022 by:Cash Withdrawal By/22008971. Download Mobile Banking bit.ly/2TYvnhB.',
    TransactionType.expense,
    2540000,
    'Cash Withdrawal By/22008971',
    _d(2022, 1, 20),
  ),
  _Case(
    'Your a/c ##533 has been Withdrawn By NPR 1,000.00 on 13/11/2026 15:18:38, Remarks eSewa Load.',
    TransactionType.expense,
    100000,
    'eSewa Load',
    _d(2026, 11, 13),
  ),
  // ---- SSF (Bikram Sambat date -> falls back to SMS timestamp) ----------
  _Case(
    'Dear Mausam Adhikari, NPR 5580 has been deposited in your SSF account 2078*****34 for 2079-Falgun on 2079.12.12 from your employer ExtensoData Pvt. Ltd. Thank you!',
    TransactionType.income,
    558000,
    'ExtensoData Pvt. Ltd',
    _ts,
  ),
  _Case(
    'Dear Mausam Adhikari, NPR 3875 has been deposited in your SSF account 2078*****34 for 2079-Bhadra on 2079.06.14 from your employer ExtensoData Pvt. Ltd. Thank you!',
    TransactionType.income,
    387500,
    'ExtensoData Pvt. Ltd',
    _ts,
  ),
  // ---- Mobile payments (via Laxmi / NBL) --------------------------------
  _Case(
    'Dear Customer, Your ###5175 has been debited by NPR 1,500.00 on 15/02/2024 10:25:33. Remarks:eSewa Payment. Laxmi Bank',
    TransactionType.expense,
    150000,
    'eSewa Payment',
    _d(2024, 2, 15),
  ),
  _Case(
    'Dear MAUSAM,##001 debited NPR 2,500.00 18/02/2024 15:30,KHALTI DIGITAL WALLET.  NBL',
    TransactionType.expense,
    250000,
    'KHALTI DIGITAL WALLET',
    _d(2024, 2, 18),
  ),
  _Case(
    'Dear Customer, Your ###5175 has been debited by NPR 800.00 on 17/02/2024 14:20:15. Remarks:FONEPAY/Payment. Laxmi Bank',
    TransactionType.expense,
    80000,
    'FONEPAY/Payment',
    _d(2024, 2, 17),
  ),
  // ---- Salary / transfer ------------------------------------------------
  _Case(
    'Dear Customer, Your ###5175 has been credited by NPR 45,000.00 on 01/02/2024. Remarks:SALARY/FEB2024/ACME CORP. Laxmi Bank',
    TransactionType.income,
    4500000,
    'SALARY/FEB2024/ACME CORP',
    _d(2024, 2, 1),
  ),
  _Case(
    'Dear MAUSAM,##001 credited NPR 25,000.00 05/02/2024 09:15,IBFT:TRANSFER FROM JOHN DOE.  NBL',
    TransactionType.income,
    2500000,
    'IBFT:TRANSFER FROM JOHN DOE',
    _d(2024, 2, 5),
  ),
  _Case(
    'Your a/c ##533 is Credited By NPR 15,000.00 on 10/02/2024 by:IPS/ConnectIPS. Download Mobile Banking bit.ly/2TYvnhB.',
    TransactionType.income,
    1500000,
    'IPS/ConnectIPS',
    _d(2024, 2, 10),
  ),
  // ---- CIT ("Rs" resolved to the user's base currency; BS date -> SMS ts)
  _Case(
    "Dear sir/ma'am Your CIT No ****** OF KBB has been CR Rs 10000.00 of month 2083/07/12 & your balance is Rs. 73000.00.",
    TransactionType.income,
    1000000,
    null,
    _ts,
  ),
  // ---- Connected-device Nepal regression shapes ------------------------
  _Case(
    'GSM Data Pack_11GB_30days has been activated successfully on 9840361144,329.00Rupees has been deducted from balance. Offer is valid till 2026/12/13.',
    TransactionType.expense,
    32900,
    null,
    _ts,
  ),
  _Case(
    'Service Number 9840361144 has been credited for 441.14Rupees, your new balance is 480.87Rupees.',
    TransactionType.income,
    44114,
    null,
    _ts,
  ),
  _Case(
    'Dear MAUSAM, AC ###505652256, NPR 315.25 withdrawn on 11/10/2026 21:11:39 for Fund Trf to NABIL BANK LTD. Siddhartha Bank',
    TransactionType.expense,
    31525,
    null,
    _d(2026, 10, 11),
  ),
  _Case(
    'Dear MAUSAM, AC ###505652256, NPR 1,000.00 deposited on 28/09/2026 11:41:18 for Fund Trf frm NABIL BANK LTD. Siddhartha Bank',
    TransactionType.income,
    100000,
    null,
    _d(2026, 9, 28),
  ),
];

void main() {
  setUpAll(() {
    final dir = Directory('assets/sms_templates/kenya');
    final index =
        jsonDecode(File('${dir.path}/index.json').readAsStringSync()) as List;
    final texts =
        index.map((f) => File('${dir.path}/$f').readAsStringSync()).toList();
    registry = TemplateRegistry.fromTemplateJson(texts);
  });

  for (var i = 0; i < _cases.length; i++) {
    final c = _cases[i];
    test('nepal #$i parses to ${c.type.name} ${c.minor}', () async {
      final r =
          await registry.parse('UNKNOWN', c.body, _ts, defaultCurrency: 'NPR');
      expect(r, isA<ParseSuccess>(),
          reason: 'message #$i should parse, got: $r');
      final t = (r as ParseSuccess).transaction;
      expect(t.type, c.type, reason: 'type #$i');
      expect(t.amountMinorUnits, c.minor, reason: 'amount #$i');
      expect(t.currency, 'NPR', reason: 'currency #$i');
      expect(t.currencyDeclared, isTrue, reason: 'currency declared #$i');
      expect(t.merchant, c.merchant, reason: 'merchant #$i');
      expect(t.timestamp, c.date, reason: 'date #$i');
    });
  }

  // The ambiguous "Rs" token must NOT be stamped as a declared currency when
  // no base currency is supplied — the row stays undeclared for review.
  test('nepal "Rs" without a base currency stays undeclared', () async {
    final body =
        "Dear sir/ma'am Your CIT No ****** OF KBB has been CR Rs 10000.00 of month 2083/07/12 & your balance is Rs. 73000.00.";
    final r = await registry.parse('UNKNOWN', body, _ts);
    expect(r, isA<ParseSuccess>());
    final t = (r as ParseSuccess).transaction;
    expect(t.amountMinorUnits, 1000000);
    expect(t.currencyDeclared, isFalse);
  });
}
