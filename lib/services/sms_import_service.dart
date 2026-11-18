// lib/services/sms_import_service.dart
//
// Bridges the native SMS capture plugin and the Dart parser engine, then
// persists parsed candidates into the sms_inbox table for user review.
//
// This service is the only place that talks to both the plugin and the
// parser. AppProvider calls it inside its mutex; the UI never touches the
// plugin or parser directly.
import 'dart:convert';
import 'dart:isolate';

import 'package:expensy_sms/expensy_sms.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

import '../database/db_helper.dart';
import '../models/models.dart';
import 'sms_parser/sms_parser.dart';

/// Loads the built-in Kenya template pack from assets and builds a
/// [TemplateRegistry]. Cached after the first load.
Future<TemplateRegistry> loadTemplateRegistry() async {
  final indexText =
      await rootBundle.loadString('assets/sms_templates/kenya/index.json');
  final files = (jsonDecode(indexText) as List).cast<String>();
  final texts = <String>[];
  for (final f in files) {
    texts.add(await rootBundle.loadString('assets/sms_templates/kenya/$f'));
  }
  return TemplateRegistry.fromTemplateJson(texts);
}

/// Scans the device inbox, parses each message, dedups against the stored
/// inbox, and persists new pending candidates.
///
/// Returns the list of newly inserted [SmsInboxItem]s (empty when the inbox
/// is already fully processed).
class SmsImportService {
  final TemplateRegistry _registry;

  SmsImportService(this._registry);

  /// Scans up to [limit] recent inbox messages and stores any that are new.
  ///
  /// A message is "new" when its `rawHash` is not already in the inbox.
  /// Every message is surfaced as a candidate — including ones the parser
  /// could not classify (`noRoute`) — so the user can review the full inbox
  /// and manually add details for senders the templates don't cover yet.
  ///
  /// [senderPrefs] (per-sender preferences) filter messages before insert:
  /// a sender with parsing denied is skipped entirely, and a message whose
  /// classified kind (otp / promotional / personal) the user acknowledged
  /// with "don't show again" is skipped — while transactional messages from
  /// the same sender still surface.
  ///
  /// [autoHideOtp] (global, default on) additionally skips messages the
  /// classifier labels as OTP, without any per-sender acknowledgement.
  ///
  /// Kind suppression is applied *after* parsing: a message the parser
  /// actually resolved into a transaction (`parsedType != null`) is never
  /// hidden, no matter what the classifier thinks. The classifier is only
  /// consulted for messages that did not parse, so a mislabel can at worst
  /// hide a non-transaction — never money.
  Future<List<SmsInboxItem>> scanAndImport({
    int limit = 500,
    Map<String, SmsSenderPref> senderPrefs = const {},
    bool autoHideOtp = true,
  }) async {
    final messages = await ExpensySms.scanSms(limit: limit);
    if (messages.isEmpty) return const [];
    final existing = await DBHelper.getSmsInbox();
    final seen = existing.map((e) => e.rawHash).toSet();

    // Parse off the UI isolate: the template engine is CPU-bound and a
    // 500-message scan must not block the frame pipeline. Only the DB
    // inserts stay on the main isolate.
    final toInsert = await Isolate.run(
      () => _processBatch(messages, _registry, senderPrefs, seen, autoHideOtp),
    );

    for (final item in toInsert) {
      await DBHelper.insertSmsInbox(item);
    }
    return toInsert;
  }

  /// Parses a single message (used by live capture). Returns the candidate
  /// (not yet persisted); unclassified messages come back as low-confidence
  /// "needs review" items so nothing is silently dropped.
  Future<SmsInboxItem> parseOne(SmsMessage msg) => _parseToItem(_registry, msg);
}

/// Pure per-message pipeline: parse → dedup → sender/kind suppression.
/// Runs inside [Isolate.run] so the CPU-bound template engine never blocks
/// the UI thread. All inputs and outputs are plain data (isolate-sendable).
Future<List<SmsInboxItem>> _processBatch(
  List<SmsMessage> messages,
  TemplateRegistry registry,
  Map<String, SmsSenderPref> prefs,
  Set<String> seen,
  bool autoHideOtp,
) async {
  final out = <SmsInboxItem>[];
  for (final msg in messages) {
    final pref = prefs[msg.sender];
    if (pref != null && !pref.parseAllowed) continue; // hard deny
    final item = await _parseToItem(registry, msg);
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
  return out;
}

Future<SmsInboxItem> _parseToItem(TemplateRegistry registry, SmsMessage msg) async {
  final ts = msg.timestamp > 0
      ? DateTime.fromMillisecondsSinceEpoch(msg.timestamp)
      : DateTime.now();
  final result = await registry.parse(msg.sender, msg.body, ts);

  if (result is ParseFailure) {
    // noRoute = the gate found no transaction cues → surface as a
    // low-confidence candidate so the user can still review it.
    // noMatch / incomplete = transaction-shaped but extraction failed.
    return SmsInboxItem(
      id: const Uuid().v4(),
      senderId: msg.sender,
      body: msg.body,
      rawHash: await rawHashFor(msg.sender, msg.body),
      smsTimestamp: msg.timestamp,
      confidence: 'failed',
      reviewReason: result.reason.name,
      status: 'pending',
    );
  }

  final tx = (result as ParseSuccess).transaction;
  return SmsInboxItem(
    id: const Uuid().v4(),
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
}

/// Convenience: build a service with the built-in registry.
Future<SmsImportService> createSmsImportService() async =>
    SmsImportService(await loadTemplateRegistry());
