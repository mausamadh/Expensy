/// Port for the current time.
///
/// Domain and application code must obtain "now" through this interface
/// instead of calling `DateTime.now()` directly, so tests can run with a
/// deterministic [FakeClock] (see `test/helpers/fake_clock.dart`).
abstract interface class Clock {
  /// Current local time.
  DateTime now();

  /// Current UTC time.
  DateTime nowUtc();
}
