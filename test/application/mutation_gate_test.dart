import 'package:finwick/adapters/time/system_clock.dart';
import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_clock.dart';

void main() {
  group('MutationGate', () {
    test('serializes concurrent mutations', () async {
      final gate = MutationGate();
      final order = <String>[];

      Future<void> mutation(String name, int ms) => gate.run(() async {
            order.add('$name-start');
            await Future<void>.delayed(Duration(milliseconds: ms));
            order.add('$name-end');
          });

      await Future.wait([
        mutation('a', 30),
        mutation('b', 10),
        mutation('c', 5),
      ]);

      // Each mutation must run to completion before the next starts.
      expect(order, [
        'a-start', 'a-end',
        'b-start', 'b-end',
        'c-start', 'c-end',
      ]);
    });

    test('nested gated calls do not deadlock', () async {
      final gate = MutationGate();
      var inner = 0;

      final result = await gate.run<int>(() async {
        inner = await gate.run<int>(() async => 42);
        return inner + 1;
      });

      expect(result, 43);
    });

    test('errors propagate to the caller', () async {
      final gate = MutationGate();
      await expectLater(
        gate.run<int>(() async => throw StateError('boom')),
        throwsStateError,
      );
      // The queue must remain usable after an error.
      expect(await gate.run<int>(() async => 7), 7);
    });
  });

  group('Clock', () {
    test('SystemClock returns current time', () {
      final before = DateTime.now();
      final now = const SystemClock().now();
      final after = DateTime.now();
      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
      expect(const SystemClock().nowUtc().isUtc, isTrue);
    });

    test('FakeClock is deterministic and advanceable', () {
      final clock = FakeClock(DateTime(2026, 1, 1, 12));
      expect(clock.now(), DateTime(2026, 1, 1, 12));
      clock.advance(days: 2, hours: 3);
      expect(clock.now(), DateTime(2026, 1, 3, 15));
      clock.setTo(DateTime(2030, 6, 15, 8, 30));
      expect(clock.now(), DateTime(2030, 6, 15, 8, 30));
      expect(clock.nowUtc().isUtc, isTrue);
    });

    test('FakeClock satisfies the Clock port', () {
      final Clock c = FakeClock();
      expect(c.now(), isA<DateTime>());
    });
  });
}
