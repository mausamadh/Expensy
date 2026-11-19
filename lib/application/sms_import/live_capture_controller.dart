// lib/application/sms_import/live_capture_controller.dart
//
// LiveCaptureController: subscribes to the [SmsSource] live-capture stream,
// parses each incoming message with the pure [SmsInboxPipeline], dedups by
// raw hash, applies per-sender parse-allow + kind-suppression + global OTP
// auto-hide, and persists new items through the [SmsInboxRepository] port.
//
// The controller reads the *current* view-model state through the supplied
// callbacks (so it never captures stale values) and reports new items back
// through [onInserted] so the view model can reassign its in-memory list.

import 'dart:async';

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_inbox_pipeline.dart';
import 'package:finwick/domain/sms_import/sms_kind_classifier.dart';

class LiveCaptureController {
  LiveCaptureController({
    required this.source,
    required this.pipeline,
    required this.inboxRepo,
    required this.gate,
    required this.isSenderAllowed,
    required this.isKindSuppressed,
    required this.autoHideOtp,
    required this.defaultCurrency,
    required this.onInserted,
  });

  final SmsSource source;
  final SmsInboxPipeline pipeline;
  final SmsInboxRepository inboxRepo;
  final MutationGate gate;

  /// Whether the sender is allowed to be parsed (current view-model state).
  final bool Function(String senderId) isSenderAllowed;
  /// Whether a message kind is suppressed for the sender.
  final bool Function(String senderId, String kind) isKindSuppressed;
  /// Current global OTP auto-hide flag.
  final bool Function() autoHideOtp;
  /// Default currency for parsing.
  final String Function() defaultCurrency;
  /// Called with each newly-inserted item (view model refreshes state).
  final void Function(SmsInboxItem item) onInserted;

  StreamSubscription<SmsMessage>? _sub;

  bool get isRunning => _sub != null;

  Future<void> start() async {
    if (_sub != null) return;
    _sub = source.startLiveCapture().listen(_onMessage);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await source.stopLiveCapture();
  }

  Future<void> _onMessage(SmsMessage msg) async {
    if (!isSenderAllowed(msg.sender)) return;

    final item = await pipeline.parseOne(msg, defaultCurrency: defaultCurrency());
    final existing = await inboxRepo.getByHash(item.rawHash);
    if (existing != null) return;

    if (item.parsedType == null) {
      final kind = SmsKindClassifier.classify(msg.body).name;
      if (kind == 'otp' && autoHideOtp()) return;
      if (isKindSuppressed(msg.sender, kind)) return;
    }

    await gate.run(() async {
      await inboxRepo.insert(item);
    });
    onInserted(item);
  }
}
