// Pure per-message SMS pipeline: parse → dedup → sender/kind suppression.
//
// Lives in the domain (no Flutter, plugin, or DB imports). The application
// layer runs it inside [Isolate.run] so the CPU-bound template engine never
// blocks the UI thread. All inputs and outputs are plain, isolate-sendable
// data.
import '../shared/uuid.dart';
import 'sms_entities.dart';
import 'sms_parser.dart';

/// Result of running [SmsInboxPipeline.processBatch].
class SmsBatchResult {
  /// Items that passed every filter and should be persisted.
  final List<SmsInboxItem> toInsert;

  /// Changed parses for existing pending items; imported/dismissed items
  /// stay unchanged.
  final List<SmsInboxItem> toUpdate;

  const SmsBatchResult(this.toInsert, this.toUpdate);
}

/// Pure parsing + filtering pipeline for a batch of raw SMS messages.
///
/// A message is surfaced as a candidate when:
///  * its sender has not denied parsing (hard deny skips the whole sender),
///  * its `rawHash` is not already in [seen] (dedup), and
///  * if the parser could not resolve a transaction (`parsedType == null`),
///    the classifier's kind is not globally auto-hidden (OTP) and not
///    per-sender suppressed.
///
/// Kind suppression is applied *after* parsing: a message the parser
/// actually resolved into a transaction is never hidden, no matter what the
/// classifier thinks. The classifier is only consulted for messages that did
/// not parse, so a mislabel can at worst hide a non-transaction — never
/// money.
class SmsInboxPipeline {
  final TemplateRegistry _registry;
  final Uuid _uuid;

  SmsInboxPipeline(this._registry, [Uuid? uuid]) : _uuid = uuid ?? Uuid();

  /// Processes [messages] and returns the items that should be persisted.
  ///
  /// [senderPrefs] maps sender id → preference. [seen] is the set of raw
  /// hashes already in the inbox (mutated: newly-accepted hashes are added).
  /// [existingItems] maps hashes to persisted candidates; only pending
  /// candidates are refreshed when their parse changes.
  /// [autoHideOtp] (global, default on) skips classifier-labelled OTPs
  /// without per-sender acknowledgement. [defaultCurrency] resolves
  /// ambiguous rupee abbreviations in fallback-matched rows.
  Future<SmsBatchResult> processBatch(
    List<SmsMessage> messages,
    Map<String, SmsSenderPref> senderPrefs,
    Set<String> seen, {
    bool autoHideOtp = true,
    String? defaultCurrency,
    List<SmsLearningProposal> learningProposals = const [],
    Map<String, SmsInboxItem> existingItems = const {},
  }) async {
    final out = <SmsInboxItem>[];
    final updates = <SmsInboxItem>[];
    final updatedHashes = <String>{};
    for (final msg in messages) {
      final pref = senderPrefs[msg.sender];
      if (pref != null && !pref.parseAllowed) continue; // hard deny
      final item = await parseOne(
        msg,
        defaultCurrency: defaultCurrency,
        learningProposals: learningProposals,
      );
      final existing = existingItems[item.rawHash];
      if (existing != null) {
        if (existing.status == 'pending' &&
            updatedHashes.add(item.rawHash) &&
            _parseFieldsDiffer(existing, item)) {
          updates.add(_withExistingIdentity(existing, item));
        }
        continue;
      }
      if (seen.contains(item.rawHash)) continue; // already processed
      if (item.parsedType == null) {
        final kind = SmsKindClassifier.classify(msg.body).name;
        // Global OTP auto-hide: OTPs are noise by default, no per-sender
        // acknowledgement needed.
        if (kind == 'otp' && autoHideOtp) continue;
        if (pref != null && pref.suppressedKinds.contains(kind)) {
          continue; // acknowledged noise kind — skip
        }
      }
      seen.add(item.rawHash);
      out.add(item);
    }
    return SmsBatchResult(out, updates);
  }

  bool _parseFieldsDiffer(SmsInboxItem existing, SmsInboxItem parsed) =>
      existing.parsedType != parsed.parsedType ||
      existing.parsedAmountMinorUnits != parsed.parsedAmountMinorUnits ||
      existing.parsedCurrency != parsed.parsedCurrency ||
      existing.parsedMerchant != parsed.parsedMerchant ||
      existing.parsedReference != parsed.parsedReference ||
      existing.parsedDate != parsed.parsedDate ||
      existing.confidence != parsed.confidence ||
      existing.reviewReason != parsed.reviewReason ||
      existing.templateId != parsed.templateId;

  SmsInboxItem _withExistingIdentity(
    SmsInboxItem existing,
    SmsInboxItem parsed,
  ) =>
      SmsInboxItem(
        id: existing.id,
        senderId: existing.senderId,
        body: existing.body,
        rawHash: existing.rawHash,
        smsTimestamp: existing.smsTimestamp,
        parsedType: parsed.parsedType,
        parsedAmountMinorUnits: parsed.parsedAmountMinorUnits,
        parsedCurrency: parsed.parsedCurrency,
        parsedMerchant: parsed.parsedMerchant,
        parsedReference: parsed.parsedReference,
        parsedDate: parsed.parsedDate,
        confidence: parsed.confidence,
        reviewReason: parsed.reviewReason,
        templateId: parsed.templateId,
        status: existing.status,
        importedTxId: existing.importedTxId,
        createdAt: existing.createdAt,
      );

  /// Parses a single message (used by live capture). Returns the candidate
  /// (not yet persisted); unclassified messages come back as low-confidence
  /// "needs review" items so nothing is silently dropped.
  Future<SmsInboxItem> parseOne(SmsMessage msg,
      {String? defaultCurrency,
      List<SmsLearningProposal> learningProposals = const []}) async {
    final ts = msg.timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(msg.timestamp)
        : DateTime.now();
    final result = await _registry.parse(msg.sender, msg.body, ts,
        defaultCurrency: defaultCurrency);

    if (result is ParseFailure) {
      // noRoute = the gate found no transaction cues → surface as a
      // low-confidence candidate so the user can still review it.
      // noMatch / incomplete = transaction-shaped but extraction failed.
      var item = SmsInboxItem(
        id: _newId(),
        senderId: msg.sender,
        body: msg.body,
        rawHash: await rawHashFor(msg.sender, msg.body),
        smsTimestamp: msg.timestamp,
        confidence: 'failed',
        reviewReason: result.reason.name,
        status: 'pending',
      );
      final match = const SmsLearningMatcher()
          .match(msg.sender, msg.body, learningProposals);
      if (match != null) {
        item = const SmsLearningMatcher().apply(item, match);
      }
      return item;
    }

    final tx = (result as ParseSuccess).transaction;
    var item = SmsInboxItem(
      id: _newId(),
      senderId: msg.sender,
      body: msg.body,
      rawHash: tx.rawHash,
      smsTimestamp: msg.timestamp,
      parsedType: tx.type.name,
      parsedAmountMinorUnits: tx.amountMinorUnits,
      parsedCurrency: tx.currency,
      parsedMerchant: tx.merchant,
      parsedReference: tx.reference,
      parsedDate: tx.timestamp,
      confidence: tx.confidence.name,
      reviewReason: tx.reviewReason,
      templateId: result.templateId,
      status: 'pending',
    );
    final match = const SmsLearningMatcher()
        .match(msg.sender, msg.body, learningProposals);
    if (match != null) {
      item = const SmsLearningMatcher().apply(item, match);
    }
    return item;
  }

  /// UUID v4 for new inbox items.
  String _newId() => _uuid.v4();
}
