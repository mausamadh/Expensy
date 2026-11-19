import 'dart:async';

/// Serializes database and balance mutations (AGENTS.md rule 2).
///
/// Zone-based mutex: a mutation already running inside the gate may call
/// other gated mutations without deadlocking (the zone value marks the
/// critical section). Never replace this with a simple counter lock —
/// re-entrant counter locks deadlock on the second acquire.
///
/// Registered as a singleton in the composition root; use cases run their
/// DB/balance work inside [run].
class MutationGate {
  MutationGate();

  static const _zoneKey = #expensyMutationGate;
  Future<void> _queue = Future.value();

  /// Runs [action] serialized with all other gated mutations.
  ///
  /// Nested calls from within an already-running gated action execute
  /// immediately (they are already inside the critical section).
  Future<T> run<T>(Future<T> Function() action) async {
    if (Zone.current[_zoneKey] == true) {
      return await action();
    }
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        final result = await runZoned(
          () => action(),
          zoneValues: {_zoneKey: true},
        );
        completer.complete(result);
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }
}
