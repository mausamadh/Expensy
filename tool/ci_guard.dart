// tool/ci_guard.dart
// note: CI guard script to audit code hygiene, hard-coded colors, UI DB imports, and raw dialogs.

import 'dart:io';

void main(List<String> args) {
  final enforce = args.contains('--enforce');
  stdout.writeln('=== Expensy Code Hygiene & CI Guard (Mode: ${enforce ? "ENFORCE" : "REPORT-ONLY"}) ===\n');

  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('Error: lib/ directory not found.');
    exit(1);
  }

  int hardcodedColorCount = 0;
  int isDarkCount = 0;
  int dbImportInUiCount = 0;
  int rawAlertDialogCount = 0;
  int domainPurityViolations = 0;
  int applicationIsolationViolations = 0;
  int presentationAdapterViolations = 0;

  final files = libDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final content = file.readAsStringSync();
    final lines = content.split('\n');

    final isTheme = path.contains('/theme/');
    final isScreen = path.contains('/screens/');
    final isWidget = path.contains('/widgets/');
    final isDomain = path.contains('/domain/');
    final isApplication = path.contains('/application/');
    final isPresentation =
        path.contains('/screens/') ||
        path.contains('/widgets/') ||
        path.contains('/presentation/');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().startsWith('//')) continue;

      // 1. Hardcoded colors outside lib/theme/
      if (!isTheme && (line.contains('Color(0x') || line.contains('Color(0X'))) {
        hardcodedColorCount++;
      }

      // 2. isDark ternaries in screens/widgets
      if ((isScreen || isWidget) && line.contains('isDark ?')) {
        isDarkCount++;
      }

      // 3. UI importing DB layer
      if (isScreen || isWidget) {
        if (line.contains("import '../database/") ||
            line.contains('import "package:finwick/database/') ||
            line.contains("import 'package:finwick/database/")) {
          dbImportInUiCount++;
          stdout.writeln('  [DB in UI] $path:${i + 1}: ${line.trim()}');
        }
      }

      // 4. Raw AlertDialog
      if ((isScreen || isWidget) && line.contains('AlertDialog(')) {
        rawAlertDialogCount++;
      }

      // 5. Hexagonal layering (HEXAGONAL_MIGRATION_PLAN.md §3)
      //    domain/ must be pure Dart: no Flutter, Drift, plugins, l10n, or
      //    any other app layer (checked by path segment so relative imports
      //    are caught too).
      if (isDomain && line.contains('import ')) {
        const forbidden = [
          'package:flutter/',
          'package:drift/',
          'package:expensy_sms/',
          'package:expensy_saf/',
          'package:shared_preferences/',
          'package:sqflite/',
          'package:workmanager/',
          'package:flutter_local_notifications/',
          'adapters/',
          'application/',
          'providers/',
          'database/',
          'screens/',
          'widgets/',
          'l10n/',
        ];
        if (forbidden.any(line.contains)) {
          domainPurityViolations++;
          stdout.writeln('  [Domain purity] $path:${i + 1}: ${line.trim()}');
        }
      }

      // 6. application/ may depend on domain only — never adapters or UI.
      if (isApplication && line.contains('import ')) {
        if (line.contains('package:finwick/adapters/') ||
            line.contains('package:finwick/screens/') ||
            line.contains('package:finwick/widgets/') ||
            line.contains('package:finwick/presentation/') ||
            line.contains('package:finwick/database/')) {
          applicationIsolationViolations++;
          stdout.writeln('  [Application isolation] $path:${i + 1}: ${line.trim()}');
        }
      }

      // 7. presentation/ must not import adapters (composition root is the
      //    only place that may construct adapters).
      if (isPresentation &&
          line.contains('import ') &&
          line.contains('package:finwick/adapters/')) {
        presentationAdapterViolations++;
        stdout.writeln('  [Presentation→Adapters] $path:${i + 1}: ${line.trim()}');
      }
    }
  }

  stdout.writeln('\n--- Audit Summary ---');
  stdout.writeln('Hardcoded Color(0x...) outside theme: $hardcodedColorCount');
  stdout.writeln('isDark ? ternaries in UI:             $isDarkCount');
  stdout.writeln('DB layer imports directly in UI:      $dbImportInUiCount');
  stdout.writeln('Raw AlertDialog uses:                 $rawAlertDialogCount');
  stdout.writeln('Domain purity violations:             $domainPurityViolations');
  stdout.writeln('Application isolation violations:     $applicationIsolationViolations');
  stdout.writeln('Presentation→Adapters violations:     $presentationAdapterViolations');

  if (enforce) {
    final failed = dbImportInUiCount > 0 ||
        domainPurityViolations > 0 ||
        applicationIsolationViolations > 0 ||
        presentationAdapterViolations > 0;
    if (failed) {
      stderr.writeln('\nFAILED: CI guard enforcement failed on rule violations.');
      exit(1);
    }
  }

  stdout.writeln('\nCI guard completed successfully.');
}
