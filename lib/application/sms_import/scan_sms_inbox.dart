// lib/application/sms_import/scan_sms_inbox.dart
//
// ScanSmsInbox use case: pulls raw SMS from the [SmsSource] port, runs the
// pure [SmsInboxPipeline] in a background isolate, and persists the new inbox
// items through the [SmsInboxRepository] port.
//
// The pipeline itself is pure domain (no I/O); this use case is the
// application-layer orchestration that wires the ports together and applies
// the concurrency gate around the persistence step.

import 'dart:isolate';

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_inbox_pipeline.dart';
import 'package:finwick/domain/sms_import/sms_parser.dart';

class SmsScanResult {
  const SmsScanResult({
    required this.insertedCount,
    required this.refreshedItemIds,
  });

  final int insertedCount;
  final List<String> refreshedItemIds;
}

/// Runs the pure [SmsInboxPipeline] over a batch of messages.
Future<SmsBatchResult> _runPipeline(
  List<SmsMessage> messages,
  Map<String, SmsSenderPref> senderPrefs,
  Set<String> seen,
  TemplateRegistry registry,
  bool autoHideOtp,
  String defaultCurrency,
  List<SmsLearningProposal> learningProposals,
  Map<String, SmsInboxItem> existingItems,
) async {
  final pipeline = SmsInboxPipeline(registry);
  return pipeline.processBatch(
    messages,
    senderPrefs,
    seen,
    autoHideOtp: autoHideOtp,
    defaultCurrency: defaultCurrency,
    learningProposals: learningProposals,
    existingItems: existingItems,
  );
}

/// Runs [_runPipeline] in a background isolate.
///
/// Defined at top level so the closure passed to [Isolate.run] has a null
/// context: it captures only the sendable parameters, never the enclosing
/// [ScanSmsInbox] instance (which holds a [MutationGate] whose internal Future
/// is not sendable across the isolate boundary). A closure defined inside an
/// instance method would carry `this` as its context and fail to send.
Future<SmsBatchResult> _runPipelineIsolate(
  List<SmsMessage> messages,
  Map<String, SmsSenderPref> senderPrefs,
  Set<String> seen,
  TemplateRegistry registry,
  bool autoHideOtp,
  String defaultCurrency,
  List<SmsLearningProposal> learningProposals,
  Map<String, SmsInboxItem> existingItems,
) {
  return Isolate.run(
    () => _runPipeline(
      messages,
      senderPrefs,
      seen,
      registry,
      autoHideOtp,
      defaultCurrency,
      learningProposals,
      existingItems,
    ),
  );
}

/// Scans the device SMS inbox and imports newly-seen messages.
class ScanSmsInbox {
  const ScanSmsInbox({
    required this.source,
    required this.inboxRepo,
    required this.registry,
    required this.gate,
  });

  final SmsSource source;
  final SmsInboxRepository inboxRepo;

  /// The template registry (plain data, isolate-sendable). The pipeline is
  /// constructed *inside* the isolate so its `Uuid`/`Random` never crosses
  /// the send-port boundary.
  final TemplateRegistry registry;
  final MutationGate gate;

  /// Returns new-item count and IDs of pending candidates refreshed.
  Future<SmsScanResult> call({
    int limit = 500,
    required Map<String, SmsSenderPref> senderPrefs,
    required bool autoHideOtp,
    required String defaultCurrency,
    List<SmsLearningProposal> learningProposals = const [],
    void Function(int total)? onMessagesLoaded,
  }) async {
    final messages = await source.scanSms(limit: limit);
    onMessagesLoaded?.call(messages.length);
    final existing = await inboxRepo.getAll();
    final seen = existing.map((e) => e.rawHash).toSet();
    final existingByHash = {for (final item in existing) item.rawHash: item};

    // The pipeline is pure; run it off the UI thread via the top-level
    // [_runPipelineIsolate], whose closure captures only sendable data — never
    // `this` (which holds the non-sendable [MutationGate]).
    final result = await _runPipelineIsolate(
      messages,
      senderPrefs,
      seen,
      registry,
      autoHideOtp,
      defaultCurrency,
      learningProposals,
      existingByHash,
    );

    if (result.toInsert.isEmpty && result.toUpdate.isEmpty) {
      return const SmsScanResult(insertedCount: 0, refreshedItemIds: []);
    }

    await gate.run(() async {
      for (final item in result.toUpdate) {
        await inboxRepo.update(item);
      }
      for (final item in result.toInsert) {
        await inboxRepo.insert(item);
      }
    });
    return SmsScanResult(
      insertedCount: result.toInsert.length,
      refreshedItemIds: result.toUpdate.map((item) => item.id).toList(),
    );
  }
}
