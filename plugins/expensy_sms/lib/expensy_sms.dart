import 'dart:async';
import 'package:flutter/services.dart';

/// One SMS message read from the device inbox.
class SmsMessage {
  final int id;
  final String sender;
  final String body;
  final int timestamp; // epoch millis

  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
  });

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  factory SmsMessage.fromMap(Map<String, dynamic> m) => SmsMessage(
        id: (m['id'] as num?)?.toInt() ?? 0,
        sender: (m['sender'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        timestamp: (m['timestamp'] as num?)?.toInt() ?? 0,
      );
}

/// A distinct SMS sender with the number of inbox messages from it.
class SmsSender {
  final String sender;
  final int count;

  const SmsSender({required this.sender, required this.count});

  factory SmsSender.fromMap(Map<String, dynamic> m) => SmsSender(
        sender: (m['sender'] as String?) ?? '',
        count: (m['count'] as num?)?.toInt() ?? 0,
      );
}

/// Permission state for SMS access.
class SmsPermissions {
  final bool read;
  final bool receive;
  final bool isDefaultSmsApp;

  const SmsPermissions({
    required this.read,
    required this.receive,
    required this.isDefaultSmsApp,
  });

  bool get canScan => read || isDefaultSmsApp;

  factory SmsPermissions.fromMap(Map<String, dynamic> m) => SmsPermissions(
        read: (m['read'] as bool?) ?? false,
        receive: (m['receive'] as bool?) ?? false,
        isDefaultSmsApp: (m['isDefaultSmsApp'] as bool?) ?? false,
      );
}

/// Dart API for the native `expensy_sms` plugin.
class ExpensySms {
  static const MethodChannel _channel = MethodChannel('com.ma.finwick/sms');
  static const EventChannel _events = EventChannel('com.ma.finwick/sms/events');

  /// Current permission state.
  static Future<SmsPermissions> checkPermissions() async {
    final res =
        await _channel.invokeMapMethod<String, dynamic>('checkPermissions');
    return SmsPermissions.fromMap(res ?? const {});
  }

  /// Prompts the user for READ_SMS + RECEIVE_SMS. Resolves with the new
  /// state after the user answers.
  static Future<SmsPermissions> requestPermissions() async {
    final res =
        await _channel.invokeMapMethod<String, dynamic>('requestPermissions');
    return SmsPermissions.fromMap(res ?? const {});
  }

  /// Reads inbox messages newest first, optionally continuing before a cursor.
  static Future<List<SmsMessage>> scanSms({
    int limit = 500,
    int? beforeTimestamp,
    int? beforeId,
  }) async {
    final res = await _channel.invokeListMethod<dynamic>('scanSms', {
      'limit': limit,
      if (beforeTimestamp != null) 'beforeTimestamp': beforeTimestamp,
      if (beforeId != null) 'beforeId': beforeId,
    });
    if (res == null) return const [];
    return res
        .map((e) => (e as Map).cast<String, dynamic>())
        .map(SmsMessage.fromMap)
        .toList();
  }

  /// Distinct senders in the recent inbox, most frequent first.
  static Future<List<SmsSender>> getSenders() async {
    final res = await _channel.invokeListMethod<dynamic>('getSenders');
    if (res == null) return const [];
    return res
        .map((e) => (e as Map).cast<String, dynamic>())
        .map(SmsSender.fromMap)
        .toList();
  }

  /// Starts streaming incoming SMS. Returns a stream of [SmsMessage].
  /// Requires RECEIVE_SMS. The stream stays open until [cancel] is called.
  static Stream<SmsMessage> startLiveCapture() async* {
    await _channel.invokeMethod('startLiveCapture');
    yield* _events.receiveBroadcastStream().map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return SmsMessage.fromMap(m);
    });
  }

  /// Stops live capture.
  static Future<void> stopLiveCapture() async {
    await _channel.invokeMethod('stopLiveCapture');
  }
}
