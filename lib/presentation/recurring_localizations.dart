// lib/presentation/recurring_localizations.dart
//
// Presentation-layer extension that renders a [RecurringPayment]'s frequency
// as a localized label. Kept out of the domain model (lib/models/models.dart)
// so the model stays pure Dart and can be imported by the domain layer
// (HEXAGONAL_MIGRATION_PLAN.md §3 — domain must not depend on l10n).

import '../l10n/app_localizations.dart';
import '../models/models.dart';

extension RecurringPaymentLocalization on RecurringPayment {
  /// Localized frequency label for UI rendering.
  String localizedFrequencyLabel(AppLocalizations l10n) {
    if (freqVal == 1) {
      switch (freqUnit) {
        case 'days':
          return l10n.freq_daily;
        case 'weeks':
          return l10n.recurring_weekly;
        case 'months':
          return l10n.recurring_monthly;
        case 'years':
          return l10n.freq_yearly;
      }
    }
    final unit = switch (freqUnit) {
      'days' => l10n.recurring_days,
      'weeks' => l10n.recurring_weeks,
      'months' => l10n.recurring_months,
      'years' => l10n.recurring_years,
      _ => freqUnit,
    };
    return '${l10n.recurring_every}$freqVal $unit';
  }
}
