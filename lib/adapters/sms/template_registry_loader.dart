// lib/adapters/sms/template_registry_loader.dart
//
// Adapter for the [TemplateRegistryProvider] port. Loads the built-in
// template packs from the Flutter asset bundle (rootBundle) and builds a
// [TemplateRegistry].
//
// rootBundle is a Flutter dependency, so this loader cannot live in the
// domain or application layers — it sits in the adapters layer and is
// injected into the use cases / view model through the port.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'package:finwick/domain/sms_import/ports/ports.dart';
import 'package:finwick/domain/sms_import/sms_parser.dart';

/// Loads the built-in template packs from assets and builds a
/// [TemplateRegistry].
class TemplateRegistryLoader implements TemplateRegistryProvider {
  const TemplateRegistryLoader();

  @override
  Future<TemplateRegistry> load() async {
    final indexText =
        await rootBundle.loadString('assets/sms_templates/kenya/index.json');
    final files = (jsonDecode(indexText) as List).cast<String>();
    final texts = <String>[];
    for (final f in files) {
      texts.add(await rootBundle.loadString('assets/sms_templates/kenya/$f'));
    }
    return TemplateRegistry.fromTemplateJson(texts);
  }
}
