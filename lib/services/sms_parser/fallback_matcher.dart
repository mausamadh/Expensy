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

  _AmountHit(this.amountMinorUnits, this.currency, this.directionSuffix, this.declared);
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

  static const _incomeCues = {'received', 'credited', 'deposit'};
  static final _incomePhrases = RegExp(r'\bcredit\s+posted\b', caseSensitive: false);

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

  // Line labels of label-based alert layouts; values run to end of line.
  // Credit/Debit lines carry the amount in layouts without an Amt label.
  static final _labeledField = RegExp(
      r'^\s*(Acct|Amt|Desc|Bal|Date|Credit|Debit)\s*:\s*(.*?)\s*$',
      multiLine: true,
      caseSensitive: false);

  // Direction evidence must be an explicit word, not a default; new cue
  // words stay flagged for review until they are added here on purpose.
  static const _directionalCues = {
    'paid', 'sent', 'bought', 'received', 'withdraw', 'debited', 'credited', 'purchase',
  };

  static Future<ParseResult> detect(
    String senderId,
    String body,
    DateTime timestamp, {
    String? defaultCurrency,
    bool preferMonthFirst = false,
  }) async {
    if (TransactionGate.blockerCues.hasMatch(body)) {
      return const ParseFailure(ParseFailureReason.noMatch, detail: 'blocker cue');
    }
    if (TransactionGate.reversalCues.hasMatch(body)) {
      return const ParseFailure(ParseFailureReason.noMatch, detail: 'reversal');
    }
    final cues = <String>{};
    for (final m in TransactionGate.transactionCues.allMatches(body)) {
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
    final hit = resolveAmount(labels, body, defaultCurrency);
    if (hit == null) {
      return const ParseFailure(ParseFailureReason.noMatch, detail: 'no amount');
    }
    final hasDebitLabel = _debitLabel.hasMatch(body);
    final hasCreditLabel = _creditLabel.hasMatch(body);
    final isProviderPayment = _paymentReceivedByProvider.hasMatch(body);
    final hasWasCharged = _wasCharged.hasMatch(body);
    final TransactionType type;
    if (hit.directionSuffix != null && hit.directionSuffix!.toUpperCase() == 'DR') {
      type = TransactionType.expense;
    } else if (hit.directionSuffix != null && hit.directionSuffix!.toUpperCase() == 'CR') {
      type = TransactionType.income;
    } else if (hasWasCharged) {
      type = TransactionType.expense;
    } else if (hasDebitLabel) {
      type = TransactionType.expense;
    } else if (hasCreditLabel) {
      type = TransactionType.income;
    } else if (isProviderPayment) {
      type = TransactionType.expense;
    } else if (cues.any(_incomeCues.contains) || _incomePhrases.hasMatch(body)) {
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
    final rawMerchant = (labels['DESC']?.isNotEmpty ?? false)
        ? labels['DESC']!
        : (_subscribedService.firstMatch(body)?.group(1)?.trim() ?? '');
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
            : parseAmountToMinorUnits(labels['BAL']!, Iso4217.exponentFor(hit.currency)),
        feeMinorUnits: null,
        timestamp: resolveTimestamp(labels, body, timestamp, preferMonthFirst),
        senderId: senderId,
        rawHash: await rawHashFor(senderId, body),
        body: body,
        parserRevision: 1,
        confidence: bookable ? ParseConfidence.high : ParseConfidence.low,
        reviewReason: bookable ? null : (!hasDirection ? 'direction' : 'amount'),
      ),
      templateId: null,
    );
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

  static _AmountHit? hitFromGrammar(RegExpMatch match, String? defaultCurrency) {
    // Real messages put the token on either side: "Ksh120" and
    // "12,500.00 KSH" are both declared money.
    final tokenText = (match.group(1) ?? '').isNotEmpty
        ? match.group(1)!
        : (match.group(5) ?? '');
    final declared = tokenText.isNotEmpty && isRecognizedCurrencyToken(tokenText);
    final currency = declared ? currencyCodeFor(tokenText) : defaultCurrency;
    final magnitude = parseAmountToMinorUnits(
        match.group(3)!, Iso4217.exponentFor(currency));
    if (magnitude == null) return null;
    final signed = (match.group(2) ?? '').isEmpty ? magnitude : -magnitude;
    final suffix = match.group(6);
    return _AmountHit(signed, currency, (suffix ?? '').isEmpty ? null : suffix,
        declared);
  }

  static DateTime resolveTimestamp(
      Map<String, String> labels, String body, DateTime smsTimestamp,
      bool preferMonthFirst) {
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
