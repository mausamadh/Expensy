import '../../domain/shared/clock.dart';

/// [Clock] backed by the system clock.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}
