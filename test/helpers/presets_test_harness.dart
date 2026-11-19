// test/helpers/presets_test_harness.dart
//
// Shared widget-test harness for the Presets view model (Phase 6).
//
// `HomeScreen` and `MainShell` embed `PresetsCarousel`, which watches
// `PresetsViewModel`. Widget tests that mount those screens must therefore
// provide a `PresetsViewModel` in addition to `AppProvider`. This helper
// builds a VM backed by an in-memory fake repository (no DB) and wraps a
// child in a `MultiProvider` exposing both notifiers.

import 'package:finwick/domain/ledger/ports/preset_repository.dart';
import 'package:finwick/models/models.dart';
import 'package:finwick/presentation/viewmodels/presets_view_model.dart';
import 'package:finwick/providers/app_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// In-memory [PresetRepository] for widget tests — no DB access.
class InMemoryPresetRepository implements PresetRepository {
  List<TransactionPreset> _presets = [];

  @override
  Future<List<TransactionPreset>> getAll() async =>
      List.unmodifiable(_presets);

  @override
  Future<void> insert(TransactionPreset preset) async {
    _presets = [..._presets, preset];
  }

  @override
  Future<void> update(TransactionPreset preset) async {
    _presets = [
      for (final p in _presets) p.id == preset.id ? preset : p,
    ];
  }

  @override
  Future<void> delete(String id) async {
    _presets = [for (final p in _presets) if (p.id != id) p];
  }
}

/// Builds a [PresetsViewModel] backed by an in-memory fake repository.
PresetsViewModel buildPresetsViewModel() =>
    PresetsViewModel(repository: InMemoryPresetRepository());

/// Wraps [child] in a `MultiProvider` exposing [app] and a fresh
/// [PresetsViewModel], so screens that watch the presets view model (e.g.
/// `PresetsCarousel` inside `HomeScreen`/`MainShell`) resolve it in tests.
Widget wrapWithPresets(AppProvider app, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppProvider>.value(value: app),
      ChangeNotifierProvider<PresetsViewModel>.value(
        value: buildPresetsViewModel(),
      ),
    ],
    child: child,
  );
}
