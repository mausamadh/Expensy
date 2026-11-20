enum SmsImportMode { conservative, balanced, automated }

enum SmsImportDecisionKind { autoImport, verificationRequired, reject }

class SmsImportDecision {
  final SmsImportDecisionKind kind;
  final String reason;

  const SmsImportDecision(this.kind, this.reason);

  bool get shouldAutoImport => kind == SmsImportDecisionKind.autoImport;
}

class SmsImportPolicy {
  const SmsImportPolicy();

  SmsImportDecision decide({
    required SmsImportMode mode,
    required String? parsedType,
    required int? amountMinorUnits,
    required String? currency,
    required String? confidence,
    required String? accountId,
    required String? categoryId,
    required String? toAccountId,
  }) {
    if (parsedType == null ||
        amountMinorUnits == null ||
        amountMinorUnits <= 0 ||
        (currency == null || currency.isEmpty)) {
      return const SmsImportDecision(SmsImportDecisionKind.verificationRequired,
          'amount, currency, or transaction direction is missing');
    }

    if (parsedType == 'transfer') {
      if (accountId == null ||
          toAccountId == null ||
          accountId.isEmpty ||
          toAccountId.isEmpty ||
          accountId == toAccountId ||
          categoryId != 'sys_transfer') {
        return const SmsImportDecision(
            SmsImportDecisionKind.verificationRequired,
            'transfer source, destination, or category is ambiguous');
      }
    } else if (parsedType != 'income' && parsedType != 'expense') {
      return const SmsImportDecision(
          SmsImportDecisionKind.reject, 'unsupported transaction direction');
    }

    if (mode == SmsImportMode.conservative) {
      if (confidence != 'high') {
        return const SmsImportDecision(
            SmsImportDecisionKind.verificationRequired,
            'conservative mode requires high parser confidence');
      }
      if (accountId == null ||
          accountId.isEmpty ||
          (parsedType != 'transfer' &&
              (categoryId == null || categoryId.isEmpty))) {
        return const SmsImportDecision(
            SmsImportDecisionKind.verificationRequired,
            'account or category is missing');
      }
      return const SmsImportDecision(SmsImportDecisionKind.autoImport,
          'high-confidence conservative import');
    }

    if (confidence == 'high') {
      if (accountId == null ||
          accountId.isEmpty ||
          (parsedType != 'transfer' &&
              (categoryId == null || categoryId.isEmpty))) {
        return const SmsImportDecision(
            SmsImportDecisionKind.verificationRequired,
            'account or category is missing');
      }
      return const SmsImportDecision(
          SmsImportDecisionKind.autoImport, 'high-confidence import');
    }

    return const SmsImportDecision(SmsImportDecisionKind.verificationRequired,
        'parser confidence requires verification');
  }
}
