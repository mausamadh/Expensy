// Temporary diagnostic: run the user's Nepalese messages through the current
// (Kenya-only) registry to see exactly which parse and with what values.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:finwick/services/sms_parser/sms_parser.dart';

final _ts = DateTime.utc(2026, 8, 15, 14, 30);

late TemplateRegistry registry;

final _messages = <String>[
  // Laxmi Bank
  'Dear Customer, Your ###5175 has been credited by NPR 2,000.00 on 05/01/2023 21:33:19. Remarks:cIPS/ACCOUNTFT:Aditi Khan. Laxmi Bank',
  'Dear Customer, Your #40035175 has been credited by NPR 5,000.00 on 06/10/24. Remarks:FON:IBFT:571197151:3725:LXBLNPKA:NARBNPKA:JANUKA K -Laxmi Sunrise',
  'Dear Customer, Your ###5175 has been debited by NPR 4,000.00 on 21/02/2022 09:35:28. Remarks:CASH WITHDRAWAL FROM ATM-. Laxmi Bank',
  'Dear Customer, Your ###5175 has been debited by NPR 3,000.00 on 08/03/2022 11:15:52. Remarks:ATM CASH WITH DRAWN FROM. Laxmi Bank',
  // NBL
  'Dear MAUSAM,##001 credited NPR 30,000.00 02/05/2023 11:28,050123043000S00L MINADEVI ADHIKARI.  NBL',
  'Dear MAUSAM,##001 debited NPR 500.00 30/10/2023 16:48,9840361144 IMEPAY:9840361144.  NBL',
  'Dear MAUSAM,##001 debited NPR 3,000.00 25/03/2022 10:14,4089271960003583@.  NBL',
  'Dear MAUSAM,##001 credited NPR 14,000.00 25/03/2022 10:36,SELF CASH.  NBL',
  // Generic bank
  'Your a/c ##533 is Credited By NPR 3,010.00 on 18/12/2021 by:IPS. Download Mobile Banking bit.ly/2TYvnhB.',
  'Your a/c ##533 is Debited By NPR 25,400.00 on 20/01/2022 by:Cash Withdrawal By/22008971. Download Mobile Banking bit.ly/2TYvnhB.',
  'Your a/c ##533 has been Withdrawn By NPR 1,000.00 on 13/11/2026 15:18:38, Remarks eSewa Load.',
  // SSF
  'Dear Mausam Adhikari, NPR 5580 has been deposited in your SSF account 2078*****34 for 2079-Falgun on 2079.12.12 from your employer ExtensoData Pvt. Ltd. Thank you!',
  'Dear Mausam Adhikari, NPR 3875 has been deposited in your SSF account 2078*****34 for 2079-Bhadra on 2079.06.14 from your employer ExtensoData Pvt. Ltd. Thank you!',
  // Mobile payments (via Laxmi/NBL)
  'Dear Customer, Your ###5175 has been debited by NPR 1,500.00 on 15/02/2024 10:25:33. Remarks:eSewa Payment. Laxmi Bank',
  'Dear MAUSAM,##001 debited NPR 2,500.00 18/02/2024 15:30,KHALTI DIGITAL WALLET.  NBL',
  'Dear Customer, Your ###5175 has been debited by NPR 800.00 on 17/02/2024 14:20:15. Remarks:FONEPAY/Payment. Laxmi Bank',
  // Salary / transfer
  'Dear Customer, Your ###5175 has been credited by NPR 45,000.00 on 01/02/2024. Remarks:SALARY/FEB2024/ACME CORP. Laxmi Bank',
  'Dear MAUSAM,##001 credited NPR 25,000.00 05/02/2024 09:15,IBFT:TRANSFER FROM JOHN DOE.  NBL',
  'Your a/c ##533 is Credited By NPR 15,000.00 on 10/02/2024 by:IPS/ConnectIPS. Download Mobile Banking bit.ly/2TYvnhB.',
  // CIT
  "Dear sir/ma'am Your CIT No ****** OF KBB has been CR Rs 10000.00 of month 2083/07/12 & your balance is Rs. 73000.00.",
];

void main() {
  setUpAll(() {
    final dir = Directory('assets/sms_templates/kenya');
    final index = jsonDecode(File('${dir.path}/index.json').readAsStringSync()) as List;
    final texts = index.map((f) => File('${dir.path}/$f').readAsStringSync()).toList();
    registry = TemplateRegistry.fromTemplateJson(texts);
  });

  test('diagnose nepal messages', () async {
    for (var i = 0; i < _messages.length; i++) {
      final body = _messages[i];
      final r = await registry.parse('UNKNOWN', body, _ts);
      final label = '[$i] ${body.substring(0, body.length > 45 ? 45 : body.length)}...';
      if (r is ParseSuccess) {
        final t = r.transaction;
        final src = r.templateId != null ? 'tpl:${r.templateId}' : 'fallback';
        // ignore: avoid_print
        print('$label => OK $src type=${t.type.name} amt=${t.amountMinorUnits} cur=${t.currency} declared=${t.currencyDeclared} merchant=${t.merchant} date=${t.timestamp}');
      } else {
        // ignore: avoid_print
        print('$label => FAIL ${(r as ParseFailure).reason.name} ${(r as ParseFailure).detail}');
      }
    }
  });
}
