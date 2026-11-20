import 'amount_parser.dart';
import 'dedup.dart';
import 'iso4217.dart';
import 'message_date_parser.dart';
import 'parsed_transaction.dart';
import 'parse_result.dart';
import 'template_parser.dart';
import 'transaction_gate.dart';
import 'transaction_type.dart';

/// One amount hit resolved from the grammar: the signed minor-unit value,
/// the currency (declared or defaulted), an optional DR/CR direction
/// suffix, and whether the text itself declared a currency token.
class _AmountHit {
  final int amountMinorUnits;
  final String? currency;
  final String? directionSuffix;
  final bool declared;

  _AmountHit(this.amountMinorUnits, this.currency, this.directionSuffix,
      this.declared);
}

/// Deliberately dumb second pass for transaction-looking messages from
/// senders with no matching template. Only the caller knows templates ran
/// first; false positives stay reviewable through the existing ledger flows.
class FallbackMatcher {
  // Full amount grammar: optional currency token (leading or trailing),
  // optional leading minus, the number, and an optional DR/CR direction
  // suffix. Group order is lead token, minus, number, trailing wrapper,
  // trailing token, suffix.
  static final _amountGrammar = RegExp(
      '($allCurrencyTokens)?\\.?[ ]?(-)?(\\d[\\d,]*(?:\\.\\d+)?)([ ]?($allCurrencyTokens))?\\.?[ ]?(DR|CR)?\\b',
      caseSensitive: false);

  static const _incomeCues = {'received', 'credited', 'deposit', 'deposited'};
  static final _incomePhrases =
      RegExp(r'\bcredit\s+posted\b', caseSensitive: false);
  static final _transferPhrases = RegExp(
      r'\b(?:fund\s*trf\s+to|credit.?card.?payment|card[_ ]payment|towards\s+(?:your\s+)?credit\s+card)\b',
      caseSensitive: false);
  static final _investmentPhrases = RegExp(
      r'\b(?:cit\s+no|c\.?i\.?t\.?\s+|retirement\s+fund|national\s+civic|investment\s+account)\b',
      caseSensitive: false);

  // "payment of X ... has been received" is a provider confirming money it
  // received from you; the income word must not book it as money in.
  static final _paymentReceivedByProvider =
      RegExp(r'payment of .* has been received', caseSensitive: false);

  // Those confirmations name the subscribed service ("for your Safaricom
  // Home Fibre Account 11900864"), which is a better merchant than the
  // sender display name.
  static final _subscribedService =
      RegExp(r'for your (.+?) Account', caseSensitive: false);

  // "was charged" is direction evidence; "will be charged" notices are not,
  // so the bare word alone never promotes a row.
  static final _wasCharged = RegExp(r'\bwas charged\b', caseSensitive: false);
  static final _debitLabel = RegExp(r'\bdebit\s*:', caseSensitive: false);
  static final _creditLabel = RegExp(r'\bcredit\s*:', caseSensitive: false);
  static final _ntDeductedRupees = RegExp(
      r'[^0-9](\d+(?:\.\d+)?)Rupees?\s+has\s+been\s+deducted',
      caseSensitive: false);
  static final _ntCreditedRupees = RegExp(
      r'(?:has\s+been\s+credited\s+for|credited\s+for)\s+(\d+(?:,\d{3})*(?:\.\d+)?)Rupees?',
      caseSensitive: false);

  // Line labels of label-based alert layouts; values run to end of line.
  // Credit/Debit lines carry the amount in layouts without an Amt label.
  static final _labeledField = RegExp(
      r'^\s*(Acct|Amt|Desc|Bal|Date|Credit|Debit)\s*:\s*(.*?)\s*$',
      multiLine: true,
      caseSensitive: false);

  static final _trailingRupeesAmount =
      RegExp(r'(\d+(?:,\d{3})*(?:\.\d+)?)\s*Rupees?', caseSensitive: false);
  static final _nprAmount =
      RegExp(r'\bNPR\s*(-?\d+(?:,\d{3})*(?:\.\d+)?)', caseSensitive: false);

  // Direction evidence must be an explicit word, not a default; new cue
  // words stay flagged for review until they are added here on purpose.
  static const _directionalCues = {
    'paid',
    'sent',
    'bought',
    'received',
    'withdraw',
    'withdrawn',
    'withdrawal',
    'debited',
    'deducted',
    'credited',
    'purchase',
    'deposit',
    'deposited',
    'cr',
    'dr',
  };

  // Standalone uppercase CR/DR before the amount ("has been CR Rs 10000.00")
  // is direction evidence; lowercase "cr"/"dr" in prose is not.
  static final _leadingCrDr = RegExp(r'\b(CR|DR)\b');

  // Merchant extraction for sender-agnostic bank alerts. First non-empty
  // match wins; trailing bank names are stripped by _stripTrailingBank.
  // "Remarks" may or may not carry a colon ("Remarks:cIPS..." vs
  // "Remarks eSewa Load"); the capture runs to end of line and the bank
  // name is stripped afterwards.
  static final _remarksMerchant =
      RegExp(r'Remarks\s*:?\s*(.+)$', caseSensitive: false);
  static final _byMerchant =
      RegExp(r'\bby\s*:\s*([^.]+)', caseSensitive: false);
  static final _nblMerchant = RegExp(
      r'\d{1,2}:\d{2}(?::\d{2})?,\s*([^.]+?)\.\s*(?:[A-Z][A-Za-z .]{2,30}\s*)?$');
  static final _ssfEmployer = RegExp(
      r'from your employer\s+(.+?)(?:\s+Thank you\b|\s*$)',
      caseSensitive: false);

  static Future<ParseResult> detect(
    String senderId,
    String body,
    DateTime timestamp, {
    String? defaultCurrency,
    bool preferMonthFirst = false,
  }) async {
    if (TransactionGate.blockerCues.hasMatch(body)) {
      return const ParseFailure(ParseFailureReason.noMatch,
          detail: 'blocker cue');
    }
    if (TransactionGate.reversalCues.hasMatch(body)) {
      return const ParseFailure(ParseFailureReason.noMatch, detail: 'reversal');
    }
    final ntDeducted = _ntDeductedRupees.firstMatch(body);
    if (ntDeducted != null) {
      final currency = defaultCurrency ?? 'NPR';
      final minor = parseAmountToMinorUnits(
          ntDeducted.group(1)!, Iso4217.exponentFor(currency));
      if (minor != null && minor > 0) {
        return ParseSuccess(
          ParsedTransaction(
            amountMinorUnits: minor,
            currency: currency,
            currencyDeclared: true,
            type: TransactionType.expense,
            timestamp: timestamp,
            senderId: senderId,
            rawHash: await rawHashFor(senderId, body),
            body: body,
            parserRevision: 1,
            confidence: ParseConfidence.high,
          ),
          templateId: null,
        );
      }
    }
    final ntCredited = _ntCreditedRupees.firstMatch(body);
    if (ntCredited != null) {
      final currency = defaultCurrency ?? 'NPR';
      final minor = parseAmountToMinorUnits(
          ntCredited.group(1)!, Iso4217.exponentFor(currency));
      if (minor != null && minor > 0) {
        return ParseSuccess(
          ParsedTransaction(
            amountMinorUnits: minor,
            currency: currency,
            currencyDeclared: true,
            type: TransactionType.income,
            timestamp: timestamp,
            senderId: senderId,
            rawHash: await rawHashFor(senderId, body),
            body: body,
            parserRevision: 1,
            confidence: ParseConfidence.high,
          ),
          templateId: null,
        );
      }
    }
    final cues = <String>{};
    for (final m in TransactionGate.transactionCues.allMatches(body)) {
      cues.add(m.group(0)!.toLowerCase());
    }
    // Standalone uppercase CR/DR is direction evidence even when no other
    // cue word is present (e.g. "has been CR Rs 10000.00").
    for (final m in TransactionGate.crDrCues.allMatches(body)) {
      cues.add(m.group(0)!.toLowerCase());
    }
    if (cues.isEmpty) {
      return const ParseFailure(ParseFailureReason.noMatch,
          detail: 'no transaction cue');
    }

    final labels = <String, String>{};
    for (final m in _labeledField.allMatches(body)) {
      labels[m.group(1)!.toUpperCase()] = m.group(2)!;
    }
    var hit = resolveAmount(labels, body, defaultCurrency);
    if (hit == null) {
      final rupees = _trailingRupeesAmount.firstMatch(body);
      if (rupees != null) {
        final currency = defaultCurrency ?? 'NPR';
        final minor = parseAmountToMinorUnits(
            rupees.group(1)!, Iso4217.exponentFor(currency));
        if (minor != null) {
          hit = _AmountHit(minor, currency, null, currency.isNotEmpty);
        }
      }
    }
    if (hit == null) {
      return const ParseFailure(ParseFailureReason.noMatch,
          detail: 'no amount');
    }
    final hasDebitLabel = _debitLabel.hasMatch(body);
    final hasCreditLabel = _creditLabel.hasMatch(body);
    final isProviderPayment = _paymentReceivedByProvider.hasMatch(body);
    final hasWasCharged = _wasCharged.hasMatch(body);
    final leadingCrDr = _leadingCrDr.firstMatch(body);
    final TransactionType type;
    if (_transferPhrases.hasMatch(body)) {
      type = TransactionType.transfer;
    } else if (hit.directionSuffix != null &&
        hit.directionSuffix!.toUpperCase() == 'DR') {
      type = TransactionType.expense;
    } else if (hit.directionSuffix != null &&
        hit.directionSuffix!.toUpperCase() == 'CR') {
      type = TransactionType.income;
    } else if (leadingCrDr != null && leadingCrDr.group(1) == 'DR') {
      type = TransactionType.expense;
    } else if (leadingCrDr != null && leadingCrDr.group(1) == 'CR') {
      type = TransactionType.income;
    } else if (hasWasCharged) {
      type = TransactionType.expense;
    } else if (hasDebitLabel) {
      type = TransactionType.expense;
    } else if (hasCreditLabel) {
      type = TransactionType.income;
    } else if (isProviderPayment) {
      type = TransactionType.expense;
    } else if (cues.any(_incomeCues.contains) ||
        _incomePhrases.hasMatch(body)) {
      type = TransactionType.income;
    } else {
      type = TransactionType.expense;
    }
    // Review bar: a declared currency plus a word that names the direction
    // is enough to count; anything vaguer waits for review.
    final hasDirection = hit.directionSuffix != null ||
        hasDebitLabel ||
        hasCreditLabel ||
        isProviderPayment ||
        hasWasCharged ||
        cues.any(_directionalCues.contains);
    // A non-positive amount is not bookable money, so it never counts.
    final bookable = hit.declared && hasDirection && hit.amountMinorUnits > 0;
    var rawMerchant = (labels['DESC']?.isNotEmpty ?? false)
        ? labels['DESC']!
        : (_subscribedService.firstMatch(body)?.group(1)?.trim() ?? '');
    if (rawMerchant.isEmpty) {
      for (final re in [
        _remarksMerchant,
        _byMerchant,
        _nblMerchant,
        _ssfEmployer,
      ]) {
        final candidate = re.firstMatch(body)?.group(1)?.trim() ?? '';
        if (candidate.isNotEmpty) {
          rawMerchant = _stripTrailingBank(candidate);
          break;
        }
      }
    }
    return ParseSuccess(
      ParsedTransaction(
        amountMinorUnits: hit.amountMinorUnits,
        currency: hit.currency,
        currencyDeclared: hit.declared,
        type: type,
        merchant: rawMerchant.isEmpty ? null : cleanMerchant(rawMerchant),
        reference: null,
        balanceMinorUnits: labels['BAL'] == null
            ? null
            : parseAmountToMinorUnits(
                labels['BAL']!, Iso4217.exponentFor(hit.currency)),
        feeMinorUnits: null,
        timestamp: resolveTimestamp(labels, body, timestamp, preferMonthFirst),
        senderId: senderId,
        rawHash: await rawHashFor(senderId, body),
        body: body,
        parserRevision: 1,
        confidence: (_investmentPhrases.hasMatch(body))
            ? ParseConfidence.low
            : (bookable ? ParseConfidence.high : ParseConfidence.low),
        reviewReason: _investmentPhrases.hasMatch(body)
            ? 'investment'
            : (bookable ? null : (!hasDirection ? 'direction' : 'amount')),
      ),
      templateId: null,
    );
  }

  // Bank signatures appended to merchant text ("... . Laxmi Bank",
  // "... -Laxmi Sunrise", "... . NBL") plus dangling terminal punctuation.
  // Only strips when the merchant ends with exactly one of these names, so
  // merchants that merely mention a bank mid-text are untouched.
  static final _trailingBank = RegExp(
      r'\s*(?:[-–—]\s*|\.\s+)?'
      r'(?:Laxmi\s+Sunrise|Laxmi\s+Bank|NBL|NIC\s+Bank|Nabil\s+Bank|'
      r'Global\s+IME\s+Bank|Himalayan\s+Bank|NMB\s+Bank|Sanima\s+Bank|'
      r'Machhapuchchhre\s+Bank|Citizen\s+Bank|Nepal\s+SBI|Bank\s+of\s+India|'
      r'ICICI\s+Bank|Standard\s+Chartered|Global\s+Bank|'
      r'Rastriya\s+Banijya\s+Bank|Nepal\s+Commerce\s+Bank|'
      r'Agricultural\s+Development\s+Bank)\s*\.?\s*$',
      caseSensitive: false);

  static String _stripTrailingBank(String merchant) {
    var m = merchant.trim();
    m = m.replaceFirst(_trailingBank, '');
    m = m.replaceFirst(RegExp(r'[-.\s]+$'), '');
    return m.trim();
  }

  static _AmountHit? resolveAmount(
      Map<String, String> labels, String body, String? defaultCurrency) {
    // Labeled layouts are structured enough to trust bare amounts.
    for (final key in const ['AMT', 'DEBIT', 'CREDIT']) {
      final value = labels[key];
      if (value != null) {
        final m = _amountGrammar.firstMatch(value);
        return m == null ? null : hitFromGrammar(m, defaultCurrency);
      }
    }
    final npr = _nprAmount.firstMatch(body);
    if (npr != null) {
      final currency = 'NPR';
      final minor =
          parseAmountToMinorUnits(npr.group(1)!, Iso4217.exponentFor(currency));
      if (minor != null) {
        return _AmountHit(minor, currency, null, true);
      }
    }
    final rupees = _trailingRupeesAmount.firstMatch(body);
    if (rupees != null) {
      final currency = defaultCurrency ?? 'NPR';
      final minor = parseAmountToMinorUnits(
          rupees.group(1)!, Iso4217.exponentFor(currency));
      if (minor != null) {
        return _AmountHit(minor, currency, null, currency.isNotEmpty);
      }
    }
    // Free text is not: without a currency token the corpus shows the
    // number is as likely an OTP, an MB count, or an activation code
    // as money.
    for (final m in _amountGrammar.allMatches(body)) {
      if ((m.group(1) ?? '').isNotEmpty || (m.group(5) ?? '').isNotEmpty) {
        return hitFromGrammar(m, defaultCurrency);
      }
    }
    return null;
  }

  static _AmountHit? hitFromGrammar(
      RegExpMatch match, String? defaultCurrency) {
    // Real messages put the token on either side: "Ksh120" and
    // "12,500.00 KSH" are both declared money.
    final tokenText = (match.group(1) ?? '').isNotEmpty
        ? match.group(1)!
        : (match.group(5) ?? '');
    final tokenCode = tokenText.isEmpty ? null : currencyCodeFor(tokenText);
    final declared =
        tokenText.isNotEmpty && isRecognizedCurrencyToken(tokenText);
    // "Rs" is an ambiguous rupee abbreviation (NPR/INR/PKR/LKR); resolve it
    // to the user's base currency when one is provided, otherwise the hit
    // stays undeclared and waits for review.
    final currency =
        declared ? (tokenCode ?? defaultCurrency) : defaultCurrency;
    final isDeclared = declared && currency != null;
    final magnitude =
        parseAmountToMinorUnits(match.group(3)!, Iso4217.exponentFor(currency));
    if (magnitude == null) return null;
    final signed = (match.group(2) ?? '').isEmpty ? magnitude : -magnitude;
    final suffix = match.group(6);
    return _AmountHit(
        signed, currency, (suffix ?? '').isEmpty ? null : suffix, isDeclared);
  }

  static DateTime resolveTimestamp(Map<String, String> labels, String body,
      DateTime smsTimestamp, bool preferMonthFirst) {
    final dateValue = labels['DATE'];
    // Credit/Debit lines carry amounts, not layout dates; without a
    // structural label the body is still worth scanning for a date.
    final hasStructuralLabels =
        labels.keys.any((k) => k != 'CREDIT' && k != 'DEBIT');
    if (dateValue != null) {
      return MessageDateParser.parseFlexibleDate(dateValue, preferMonthFirst) ??
          smsTimestamp;
    }
    if (!hasStructuralLabels) {
      return MessageDateParser.parseFlexibleDate(body, preferMonthFirst) ??
          smsTimestamp;
    }
    return smsTimestamp;
  }
}
