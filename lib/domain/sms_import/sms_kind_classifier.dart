// Classifies an SMS body into a coarse "kind" so the user can suppress
// specific kinds per sender (e.g. hide OTPs from a bank but keep its
// transactional messages). Reuses the cue regexes from [TransactionGate]
// so the classifier and the parser gate stay in agreement.
library;

import 'transaction_gate.dart';

/// Coarse message kinds. [SmsKind.transactional] is the only kind that is
/// ever worth surfacing as a candidate; the rest are suppressible noise.
enum SmsKind { transactional, otp, promotional, personal }

extension SmsKindX on SmsKind {
  String get label => switch (this) {
        SmsKind.transactional => 'Transactional',
        SmsKind.otp => 'OTP / verification',
        SmsKind.promotional => 'Promotional',
        SmsKind.personal => 'Personal',
      };
}

class SmsKindClassifier {
  // ── OTP / verification codes ────────────────────────────────────────────
  // Checked first: a bank OTP ("Your OTP is 123456, valid for 5 min")
  // contains no transaction cues, and a "verification code" message that
  // also mentions a payment must not be booked.
  static final _otpCues = RegExp(
      r'\b(?:otp|pin|password|passcode)\b'
      r'|\bone[- ]?time[- ]?(?:password|code|pin)\b'
      r'|\bverification code\b'
      r'|\b(?:activation|authorization|authorisation|auth) code\b'
      r'|\bsecurity code\b'
      r'|\bconfirm(?:ation)? code\b'
      r'|\benter the \d{4,8}\b'
      r'|\bcode is \d{4,8}\b'
      r'|\bcode:?\s*\d{4,8}\b'
      r'|\bvalid for \d+\s*(?:min|sec|hour)\b',
      caseSensitive: false);

  // ── Transactional (beyond the gate cues) ────────────────────────────────
  // [TransactionGate.transactionCues] is a conservative set used to decide
  // whether to *parse* a message. For *classification* we need a broader
  // net: a real transaction mislabelled as "personal" could be hidden by a
  // "don't show personal again" choice and lost from the ledger. The safe
  // error direction is the opposite — a promo that looks like a transaction
  // surfaces once more, but money is never silently dropped.
  static final _transactionCues = RegExp(
      // Payment / transfer confirmation phrasing (either word order).
      r'\b(?:payment|txn|transfer(?:red)?|settlement|disbursal)\b[\s\S]{0,40}\b(?:successful(?:ly)?|success|completed|done|processed|failed|rejected|initiated)\b'
      r'|\b(?:successful(?:ly)?|success|completed|processed|failed|rejected)\b[\s\S]{0,40}\b(?:payment|txn|transfer(?:red)?|settlement|disbursal)\b'
      // Currency + amount ("Rs. 500", "NPR 1,200.50", "KSh 250").
      r'|\b(?:rs|npr|ksh|usd|eur|gbp|inr|aed|jpy|cad|aud)\s*\.?\s*[\d,]+(?:\.\d+)?\b'
      // Reference / receipt identifiers ("Ref: KH123456", "Txn ID 998877").
      r'|\b(?:ref(?:erence)?|txn id|transaction id|receipt no|invoice no|order id)[:#]?\s*[a-z0-9]{4,}\b'
      // Balance statements ("Balance: Rs. 1,234").
      r'|\bbalance\b[\s\S]{0,30}\b(?:rs|npr|ksh|usd|eur|gbp|inr|aed|jpy|cad|aud)\b'
      r'|\b(?:rs|npr|ksh|usd|eur|gbp|inr|aed|jpy|cad|aud)\b[\s\S]{0,30}\bbalance\b'
      // Known payment rails / wallets.
      r'|\b(?:m-?pesa|airtel money|ecocash|halo cash|khalti|esewa|bkash|nagad|upi|swipe|pos)\b',
      caseSensitive: false);

  // ── Promotional / marketing ─────────────────────────────────────────────
  static final _promoCues = RegExp(
      r'\b(?:offer|offers|promo|promotion|deal|deals|discount|cashback|win|winner|won|prize|lottery|contest|subscribe|unsubscribe|reply stop|click here|shop now|buy now|limited time|flash sale|sale|special|bonus|airtime|recharge|top ?up|upgrade|new feature|check out|explore|learn more|opt ?in|opt ?out)\b'
      r'|\b(?:loan|credit) (?:offer|available|approved|limit)\b'
      r'|\bmake daily payments\b'
      r'|\bstoro\b'
      r'|\b(?:%|percent)\s*(?:off|discount)\b',
      caseSensitive: false);

  // ── Personal / conversational ───────────────────────────────────────────
  // Short, greeting-like, or clearly conversational messages. Kept
  // deliberately conservative: when in doubt we fall back to
  // [SmsKind.personal] only if there are no transaction cues at all.
  static final _personalCues = RegExp(
      r'\b(?:hi|hello|hey|yo|good (?:morning|afternoon|evening|night))\b'
      r'|\b(?:thanks|thank you|thx|ty|please|pls|ok|okay|yes|no|sure|maybe|lol|haha|omg|brb|ttyl|cya|see you|miss you|love you|how are you|what is up|whats up)\b'
      r'|\b(?:call|text|meet|come|going|coming|waiting|where are you|when are you)\b',
      caseSensitive: false);

  /// Classifies [body]. Precedence: OTP > transactional > promotional >
  /// personal.
  ///
  /// OTP wins over everything: an OTP message may mention a transaction
  /// ("Your OTP for this transaction is 123456") and must never be booked.
  /// Transaction cues beat promo cues: a real transaction often carries a
  /// marketing footer ("Rs. 500 credited. Enjoy 10% off!") and hiding it
  /// would lose money the user actually moved. A promo that merely mentions
  /// a purchase word ("Buy now on your purchase!") is the safe direction of
  /// error — it surfaces once, the user dismisses it as promotional, and
  /// that kind is then suppressed for the sender.
  static SmsKind classify(String body) {
    if (_otpCues.hasMatch(body)) return SmsKind.otp;
    if (TransactionGate.transactionCues.hasMatch(body) ||
        _transactionCues.hasMatch(body)) {
      return SmsKind.transactional;
    }
    if (_promoCues.hasMatch(body)) return SmsKind.promotional;
    if (_personalCues.hasMatch(body)) return SmsKind.personal;
    // No cues at all — treat as personal noise (the parser will still
    // surface it as a low-confidence candidate unless suppressed).
    return SmsKind.personal;
  }
}
