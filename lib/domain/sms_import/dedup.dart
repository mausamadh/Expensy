import 'dart:convert';
import 'package:cryptography/cryptography.dart';

final _sha256 = Sha256();

/// Stable `senderId:body` digest for dedup. Timestamp-independent, so a
/// re-delivered copy of the same message collapses onto the first.
Future<String> rawHashFor(String senderId, String body) =>
    sha256Hex('$senderId:$body');

/// Lowercase hex SHA-256 of [input].
Future<String> sha256Hex(String input) async {
  final digest = await _sha256.hash(utf8.encode(input));
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
