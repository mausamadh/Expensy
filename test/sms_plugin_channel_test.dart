// test/sms_plugin_channel_test.dart
//
// Regression test for the MethodChannel deserialization bug: the native
// plugin returns List<Map<String, Any?>>, which the standard codec decodes
// as Map<Object?, Object?> — NOT Map<String, dynamic>. The old
// `whereType<Map<String, dynamic>>()` therefore matched nothing and the
// inbox silently came back empty. These tests mock the channel with the
// real codec's map shape and assert the messages survive the round trip.
import 'package:expensy_sms/expensy_sms.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ma.finwick/sms');

  /// Builds a list of maps the way the standard codec actually decodes a
  /// Kotlin `List<Map<String, Any?>>`: keys/values are `Object?`, so the
  /// runtime type is `Map<Object?, Object?>`.
  List<Object?> nativeList(List<Map<String, Object?>> rows) =>
      rows.map((m) => <Object?, Object?>{...m}).toList();

  test('scanSms decodes codec-shaped maps (regression: empty inbox)', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'scanSms') {
        return nativeList([
          {
            'id': 5520,
            'sender': 'Khalti',
            'body': 'Khalti payment of Rs. 500 successful',
            'timestamp': 1794891768392,
          },
          {
            'id': 5519,
            'sender': 'CTZNS_Alert',
            'body': 'Your transaction of Rs. 1200 was debited',
            'timestamp': 1794919616687,
          },
        ]);
      }
      return null;
    });

    final messages = await ExpensySms.scanSms(limit: 500);

    // The old whereType<Map<String, dynamic>>() returned 0 here.
    expect(messages, hasLength(2));
    expect(messages.first.id, 5520);
    expect(messages.first.sender, 'Khalti');
    expect(messages.first.body, 'Khalti payment of Rs. 500 successful');
    expect(messages.first.timestamp, 1794891768392);
    expect(messages.last.sender, 'CTZNS_Alert');
  });

  test('getSenders decodes codec-shaped maps (regression: empty list)',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSenders') {
        return nativeList([
          {'sender': 'Khalti', 'count': 42},
          {'sender': 'CTZNS_Alert', 'count': 7},
        ]);
      }
      return null;
    });

    final senders = await ExpensySms.getSenders();

    expect(senders, hasLength(2));
    expect(senders.first.sender, 'Khalti');
    expect(senders.first.count, 42);
    expect(senders.last.sender, 'CTZNS_Alert');
  });

  test('scanSms tolerates null and empty channel results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    expect(await ExpensySms.scanSms(), isEmpty);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => <Object?>[]);
    expect(await ExpensySms.scanSms(), isEmpty);
  });

  test('scanSms forwards pagination cursors to the native reader', () async {
    Map<Object?, Object?>? arguments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'scanSms') {
        arguments = (call.arguments as Map).cast<Object?, Object?>();
      }
      return <Object?>[];
    });

    await ExpensySms.scanSms(
      limit: 250,
      beforeTimestamp: 1793520000000,
      beforeId: 8421,
    );

    expect(arguments?['limit'], 250);
    expect(arguments?['beforeTimestamp'], 1793520000000);
    expect(arguments?['beforeId'], 8421);
  });
}
