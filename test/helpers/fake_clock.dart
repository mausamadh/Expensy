import 'package:finwick/domain/shared/clock.dart';

/// Deterministic [Clock] for tests.
class FakeClock implements Clock {
  DateTime _now;

  FakeClock([DateTime? start])
      : _now = start ?? DateTime(2026, 1, 1, 12, 0, 0);

  /// Advances the fake clock by [duration].
  void advance({int days = 0, int hours = 0, int minutes = 0, int seconds = 0}) {
    _now = _now.add(
      Duration(days: days, hours: hours, minutes: minutes, seconds: seconds),
    );
  }

  /// Sets the fake clock to an exact instant.
  void setTo(DateTime instant) => _now = instant;

  @override
  DateTime now() => _now;

  @override
  DateTime nowUtc() => _now.toUtc();
}
