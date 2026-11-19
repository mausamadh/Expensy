// lib/application/sms_import/sender_pref_use_cases.dart
//
// Use cases for per-sender parsing preferences:
//   - SetSmsSenderParseAllowed: allow/deny parsing for a sender.
//   - SuppressSmsKind: hide a specific message kind for a sender.
//   - UnsuppressSmsKind: un-hide a previously suppressed kind.
//   - ResetSmsSenderPrefs: delete a sender's preference entirely.
//
// Each persists through the [SmsSenderPrefRepository] port and returns the
// updated pref list so the view model can reassign its in-memory list with a
// fresh instance (AGENTS.md rule 6).
//
// Note: the "deny dismisses all pending items for that sender" side effect is
// applied by the view model (which owns the in-memory inbox), not here.

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';

/// The transactional kind can never be suppressed (it is the whole point of
/// the inbox).
const String kTransactionalKind = 'transactional';

class SetSmsSenderParseAllowed {
  SetSmsSenderParseAllowed({
    required this.prefRepo,
    required this.gate,
    required this.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? Uuid();

  final SmsSenderPrefRepository prefRepo;
  final MutationGate gate;
  final Clock clock;
  final Uuid _uuid;

  /// Returns the updated pref list. No-op (returns [prefs] unchanged) when
  /// [senderId] is blank.
  Future<List<SmsSenderPref>> call(
    String senderId,
    bool allowed, {
    required List<SmsSenderPref> prefs,
  }) {
    return gate.run(() async {
      final id = senderId.trim();
      if (id.isEmpty) return prefs;
      SmsSenderPref? existing;
      for (final p in prefs) {
        if (p.senderId == id) {
          existing = p;
          break;
        }
      }
      if (existing != null) {
        final updated = existing.copyWith(parseAllowed: allowed);
        await prefRepo.update(updated);
        return [for (final p in prefs) p.id == updated.id ? updated : p];
      }
      final created = SmsSenderPref(
        id: _uuid.v4(),
        senderId: id,
        parseAllowed: allowed,
        createdAt: clock.now(),
      );
      await prefRepo.insert(created);
      return [...prefs, created];
    });
  }
}

class SuppressSmsKind {
  SuppressSmsKind({
    required this.prefRepo,
    required this.gate,
    required this.clock,
    Uuid? uuid,
  }) : _uuid = uuid ?? Uuid();

  final SmsSenderPrefRepository prefRepo;
  final MutationGate gate;
  final Clock clock;
  final Uuid _uuid;

  /// Returns the updated pref list. No-op for blank sender/kind and for the
  /// transactional kind (never suppressible).
  Future<List<SmsSenderPref>> call(
    String senderId,
    String kind, {
    required List<SmsSenderPref> prefs,
  }) {
    return gate.run(() async {
      final id = senderId.trim();
      final k = kind.trim();
      if (id.isEmpty || k.isEmpty || k == kTransactionalKind) return prefs;
      SmsSenderPref? existing;
      for (final p in prefs) {
        if (p.senderId == id) {
          existing = p;
          break;
        }
      }
      if (existing != null) {
        final kinds = {...existing.suppressedKinds, k};
        final updated = existing.copyWith(suppressedKinds: kinds);
        await prefRepo.update(updated);
        return [for (final p in prefs) p.id == updated.id ? updated : p];
      }
      final created = SmsSenderPref(
        id: _uuid.v4(),
        senderId: id,
        parseAllowed: true,
        suppressedKinds: {k},
        createdAt: clock.now(),
      );
      await prefRepo.insert(created);
      return [...prefs, created];
    });
  }
}

class UnsuppressSmsKind {
  UnsuppressSmsKind({required this.prefRepo, required this.gate});

  final SmsSenderPrefRepository prefRepo;
  final MutationGate gate;

  /// Returns the updated pref list. No-op when there is no pref for the
  /// sender.
  Future<List<SmsSenderPref>> call(
    String senderId,
    String kind, {
    required List<SmsSenderPref> prefs,
  }) {
    return gate.run(() async {
      final id = senderId.trim();
      final k = kind.trim();
      if (id.isEmpty || k.isEmpty) return prefs;
      SmsSenderPref? existing;
      for (final p in prefs) {
        if (p.senderId == id) {
          existing = p;
          break;
        }
      }
      if (existing == null) return prefs;
      final kinds = existing.suppressedKinds..remove(k);
      final updated = existing.copyWith(suppressedKinds: kinds);
      await prefRepo.update(updated);
      return [for (final p in prefs) p.id == updated.id ? updated : p];
    });
  }
}

class ResetSmsSenderPrefs {
  ResetSmsSenderPrefs({required this.prefRepo, required this.gate});

  final SmsSenderPrefRepository prefRepo;
  final MutationGate gate;

  /// Returns the updated pref list with the sender's pref removed. No-op when
  /// there is no pref for the sender.
  Future<List<SmsSenderPref>> call(
    String senderId, {
    required List<SmsSenderPref> prefs,
  }) {
    return gate.run(() async {
      final id = senderId.trim();
      if (id.isEmpty) return prefs;
      SmsSenderPref? existing;
      for (final p in prefs) {
        if (p.senderId == id) {
          existing = p;
          break;
        }
      }
      if (existing == null) return prefs;
      await prefRepo.delete(existing.id);
      return [for (final p in prefs) if (p.id != existing.id) p];
    });
  }
}
