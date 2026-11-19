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

/// Runs the pure [SmsInboxPipeline] over a batch of messages.
Future<SmsBatchResult> _runPipeline(
  List<SmsMessage> messages,
  Map<String, SmsSenderPref> senderPrefs,
  Set<String> seen,
  TemplateRegistry registry,
  bool autoHideOtp,
  String defaultCurrency,
) async {
  final pipeline = SmsInboxPipeline(registry);
  return pipeline.processBatch(
    messages,
    senderPrefs,
    seen,
    autoHideOtp: autoHideOtp,
    defaultCurrency: defaultCurrency,
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
) {
  return Isolate.run(
    () => _runPipeline(
      messages,
      senderPrefs,
      seen,
      registry,
      autoHideOtp,
      defaultCurrency,
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

  /// Returns the number of newly-inserted inbox items.
  Future<int> call({
    int limit = 500,
    required Map<String, SmsSenderPref> senderPrefs,
    required bool autoHideOtp,
    required String defaultCurrency,
  }) async {
    final messages = await source.scanSms(limit: limit);
    final existing = await inboxRepo.getAll();
    final seen = existing.map((e) => e.rawHash).toSet();

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
    );

    if (result.toInsert.isEmpty) return 0;

    await gate.run(() async {
      for (final item in result.toInsert) {
        await inboxRepo.insert(item);
      }
    });
    return result.toInsert.length;
  }
}
