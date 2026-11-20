// Adapter: wraps the `expensy_sms` plugin behind the domain [SmsSource]
// port, mapping plugin types into domain value objects at the boundary.
import 'dart:async';

import 'package:expensy_sms/expensy_sms.dart' as plugin;

import '../../domain/sms_import/ports/ports.dart';
import '../../domain/sms_import/sms_entities.dart';

class ExpensySmsSource implements SmsSource {
  const ExpensySmsSource();

  @override
  Future<List<SmsMessage>> scanSms({
    int limit = 500,
    int? beforeTimestamp,
    String? beforeId,
  }) async {
    final msgs = await plugin.ExpensySms.scanSms(
      limit: limit,
      beforeTimestamp: beforeTimestamp,
      beforeId: beforeId == null ? null : int.tryParse(beforeId),
    );
    return msgs.map(_toDomain).toList();
  }

  @override
  Future<List<SmsSender>> getSenders() async {
    final senders = await plugin.ExpensySms.getSenders();
    return senders
        .map((s) => SmsSender(sender: s.sender, count: s.count))
        .toList();
  }

  @override
  Future<SmsPermissions> checkPermissions() async {
    final p = await plugin.ExpensySms.checkPermissions();
    return _permsToDomain(p);
  }

  @override
  Future<SmsPermissions> requestPermissions() async {
    final p = await plugin.ExpensySms.requestPermissions();
    return _permsToDomain(p);
  }

  @override
  Stream<SmsMessage> startLiveCapture() =>
      plugin.ExpensySms.startLiveCapture().map(_toDomain);

  @override
  Future<void> stopLiveCapture() => plugin.ExpensySms.stopLiveCapture();

  SmsMessage _toDomain(plugin.SmsMessage m) => SmsMessage(
        id: m.id.toString(),
        sender: m.sender,
        body: m.body,
        timestamp: m.timestamp,
      );

  SmsPermissions _permsToDomain(plugin.SmsPermissions p) => SmsPermissions(
        read: p.read,
        receive: p.receive,
        isDefaultSmsApp: p.isDefaultSmsApp,
      );
}
