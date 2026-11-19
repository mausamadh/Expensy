// RFC 4122 version 4 UUID generation, domain-owned.
//
// Lives in the domain so both the SMS pipeline and the application-layer
// use cases can mint ids without depending on `package:uuid`. Uses
// `dart:math` Random (injectable for deterministic tests).
import 'dart:math';

class Uuid {
  final Random _random;

  Uuid([Random? random]) : _random = random ?? Random();

  /// Generates a version 4 (random) UUID string.
  String v4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
