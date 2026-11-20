import 'package:flutter/foundation.dart';

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/application/sms_import/sms_import_use_cases.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_inbox_pipeline.dart';
import 'package:finwick/domain/sms_import/sms_rule_matcher.dart';
import 'package:finwick/domain/sms_import/sms_verification.dart';
import 'package:finwick/domain/sms_import/sms_kind_classifier.dart';
import 'package:finwick/domain/sms_import/sms_import_policy.dart';
import 'package:finwick/domain/sms_import/template_registry.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';

/// Presentation-layer view model for the SMS inbox screen.
///
/// Owns the SMS state slice (inbox, rules, sender prefs, permissions,
/// scanning flag, auto-hide-OTP) and delegates every mutation to the
/// application-layer use cases. Replaces the SMS slice of `AppProvider`
/// (Phase 1 of the hexagonal migration).
///
/// Layering: this file lives in `presentation/` and imports only
/// `application/` and `domain/` — never `adapters/`. Adapters are injected
/// through the constructor by the composition root.
class SmsInboxViewModel extends ChangeNotifier {
  SmsInboxViewModel({
    required SmsSource source,
    required SmsInboxRepository inboxRepo,
    required SmsRuleRepository ruleRepo,
    required SmsSenderPrefRepository prefRepo,
    required SmsSenderAccountMappingRepository senderAccountMappingRepo,
    required SmsSettings settings,
    SmsVerificationRepository? verificationRepo,
    SmsOutboxRepository? outboxRepo,
    SmsNotificationGateway? notificationGateway,
    required LedgerGateway ledger,
    required LedgerContext ledgerContext,
    required TemplateRegistryProvider registryProvider,
    required MutationGate gate,
    required Clock clock,
  })  : _source = source,
        _inboxRepo = inboxRepo,
        _ruleRepo = ruleRepo,
        _prefRepo = prefRepo,
        _senderAccountMappingRepo = senderAccountMappingRepo,
        _settings = settings,
        _verificationRepo = verificationRepo,
        _outboxRepo = outboxRepo,
        _notificationGateway = notificationGateway,
        _ledger = ledger,
        _ledgerContext = ledgerContext,
        _registryProvider = registryProvider,
        _gate = gate,
        _clock = clock,
        _uuid = Uuid(),
        _matcher = const SmsRuleMatcher();

  final SmsSource _source;
  final SmsInboxRepository _inboxRepo;
  final SmsRuleRepository _ruleRepo;
  final SmsSenderPrefRepository _prefRepo;
  final SmsSenderAccountMappingRepository _senderAccountMappingRepo;
  final SmsSettings _settings;
  final SmsVerificationRepository? _verificationRepo;
  final SmsOutboxRepository? _outboxRepo;
  final SmsNotificationGateway? _notificationGateway;
  final LedgerGateway _ledger;
  final LedgerContext _ledgerContext;
  final TemplateRegistryProvider _registryProvider;
  final MutationGate _gate;
  final Clock _clock;
  final Uuid _uuid;
  final SmsRuleMatcher _matcher;

  // ── State ──────────────────────────────────────────────────────────────
  List<SmsInboxItem> _inbox = [];
  List<SmsRule> _rules = [];
  List<SmsSenderPref> _prefs = [];
  List<SmsSenderAccountMapping> _senderAccountMappings = [];
  bool _scanning = false;
  bool _autoHideOtp = true;
  bool _liveCaptureEnabled = false;
  bool _smsConsentResolved = false;
  bool _smsAutoImportEnabled = false;
  int _smsLoadingTotal = 0;
  int _smsLoadingLoaded = 0;
  String? _smsStatusMessage;
  bool _smsStatusIsError = false;
  List<SmsLearningProposal> _learningProposals = [];
  SmsPermissions? _permissions;
  TemplateRegistry? _registry;
  LiveCaptureController? _live;

  // ── State getters ──────────────────────────────────────────────────────
  List<SmsInboxItem> get smsInbox => _inbox;
  List<SmsRule> get smsRules => _rules;
  List<SmsSenderPref> get smsSenderPrefs => _prefs;
  List<SmsSenderAccountMapping> get smsSenderAccountMappings =>
      _senderAccountMappings;
  bool get smsScanning => _scanning;
  bool get smsAutoHideOtp => _autoHideOtp;
  bool get smsLiveCaptureEnabled => _liveCaptureEnabled;
  bool get smsConsentResolved => _smsConsentResolved;
  bool get smsAutoImportEnabled => _smsAutoImportEnabled;
  int get smsLoadingTotal => _smsLoadingTotal;
  int get smsLoadingLoaded => _smsLoadingLoaded;
  String? get smsStatusMessage => _smsStatusMessage;
  bool get smsStatusIsError => _smsStatusIsError;
  List<SmsLearningProposal> get smsLearningProposals => _learningProposals;

  bool _compatibleAccountTypes(String suggested, String existing) {
    if (suggested == existing) return true;
    const depositTypes = {'bank', 'savings'};
    return depositTypes.contains(suggested) && depositTypes.contains(existing);
  }

  String _accountSuggestionIdentity(String name) {
    const genericTerms = {
      'account',
      'accounts',
      'bank',
      'card',
      'credit',
      'current',
      'debit',
      'finance',
      'financial',
      'fund',
      'limited',
      'ltd',
      'prepaid',
      'retirement',
      'saving',
      'savings',
      'wallet',
    };
    final terms = name
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((term) => term.isNotEmpty && !genericTerms.contains(term));
    return terms.join();
  }

  String _suggestedAccountType(String sender, String body) {
    final lowerSender = sender.toLowerCase();
    if (lowerSender.contains('cit') ||
        body.contains('cit no') ||
        body.contains('citizens investment') ||
        body.contains('retirement fund')) {
      return 'savings';
    }
    if (body.contains('credit card') ||
        body.contains('card payment') ||
        body.contains('card was used') ||
        body.contains('card ending')) {
      return 'credit';
    }
    if (lowerSender.contains('khalti') ||
        lowerSender.contains('esewa') ||
        lowerSender.contains('ime') ||
        lowerSender.contains('fonepay') ||
        lowerSender.contains('namastepay')) {
      return 'wallet';
    }
    if (body.contains('debit card') || body.contains('atm')) return 'debit';
    return 'bank';
  }

  SmsPermissions? get smsPermissions => _permissions;

  // ── Load ───────────────────────────────────────────────────────────────
  /// Loads the initial state from the repositories and settings.
  Future<void> load() async {
    _inbox = await _inboxRepo.getAll();
    _rules = await _ruleRepo.getAll();
    _prefs = await _prefRepo.getAll();
    _senderAccountMappings = await _senderAccountMappingRepo.getAll();
    _autoHideOtp = await _settings.getAutoHideOtp();
    _liveCaptureEnabled = await _settings.getLiveCaptureEnabled();
    _smsConsentResolved = await _settings.getFirstRunSmsConsentResolved();
    _smsAutoImportEnabled = await _settings.getSmsAutoImportEnabled();
    _learningProposals =
        await (_verificationRepo?.getLearningProposals(status: 'active') ??
            Future<List<SmsLearningProposal>>.value(const []));
    _registry = await _registryProvider.load();
    notifyListeners();
  }

  Future<void> initializeOnStartup() async {
    try {
      await load();
      final permissions = await checkSmsPermissions();
      if (!permissions.canScan) {
        _setSmsStatus(
          'SMS access is not enabled. Open SMS Inbox and grant access to scan.',
          isError: true,
        );
        return;
      }

      final liveCaptureStarted = !_liveCaptureEnabled ||
          (permissions.receive && await _tryStartLiveCapture());
      await scanSmsInbox(limit: 5000, scanAllPages: true);
      if (!liveCaptureStarted) {
        _setSmsStatus(
          'SMS history was scanned, but live capture could not start.',
          isError: true,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('SMS startup processing failed: $error\n$stackTrace');
      _setSmsStatus(
        'SMS processing could not start. Open SMS Inbox and scan again.',
        isError: true,
      );
    }
  }

  void clearSmsStatus() {
    _smsStatusMessage = null;
    _smsStatusIsError = false;
    notifyListeners();
  }

  void _setSmsStatus(String message, {bool isError = false}) {
    _smsStatusMessage = message;
    _smsStatusIsError = isError;
    notifyListeners();
  }

  // ── Permissions ────────────────────────────────────────────────────────
  Future<SmsPermissions> checkSmsPermissions() async {
    final perms = await _source.checkPermissions();
    _permissions = perms;
    notifyListeners();
    return perms;
  }

  Future<SmsPermissions> requestSmsPermissions({
    bool scanOnGrant = true,
    bool startLiveCaptureOnGrant = true,
  }) async {
    final perms = await _source.requestPermissions();
    _permissions = perms;
    notifyListeners();
    if (perms.canScan) {
      final liveCaptureStarted = !startLiveCaptureOnGrant ||
          (perms.receive && await _tryStartLiveCapture());
      if (scanOnGrant) {
        await scanSmsInbox(limit: 5000, scanAllPages: true);
      }
      if (!liveCaptureStarted) {
        _setSmsStatus(
          'SMS history was scanned, but live capture could not start.',
          isError: true,
        );
      }
    } else if (!perms.canScan) {
      _setSmsStatus(
        'SMS access was not granted. Enable SMS access to parse messages.',
        isError: true,
      );
    }
    return perms;
  }

  // ── Senders ────────────────────────────────────────────────────────────
  Future<List<SmsSender>> getSmsSenders() => _source.getSenders();

  // ── Scan ───────────────────────────────────────────────────────────────
  Future<int> scanSmsInbox({
    int limit = 5000,
    bool scanAllPages = false,
  }) async {
    if (_scanning) return 0;
    _scanning = true;
    _smsLoadingTotal = 0;
    _smsLoadingLoaded = 0;
    _smsStatusMessage = null;
    _smsStatusIsError = false;
    notifyListeners();
    try {
      final previousIds = _inbox.map((item) => item.id).toSet();
      final registry = _registry ?? await _registryProvider.load();
      final scan = ScanSmsInbox(
        source: _source,
        inboxRepo: _inboxRepo,
        registry: registry,
        gate: _gate,
      );
      final result = await scan(
        limit: limit,
        scanAllPages: scanAllPages,
        senderPrefs: {for (final p in _prefs) p.senderId: p},
        autoHideOtp: _autoHideOtp,
        defaultCurrency: _ledgerContext.defaultCurrency,
        learningProposals: _learningProposals,
        onMessagesLoaded: (total) {
          _smsLoadingTotal = total;
          _smsLoadingLoaded = total;
          notifyListeners();
        },
      );
      _inbox = await _inboxRepo.getAll();
      final refreshedIds = result.refreshedItemIds.toSet();
      final affectedCandidates = _inbox
          .where((item) =>
              !previousIds.contains(item.id) || refreshedIds.contains(item.id))
          .toList(growable: false);
      final importedCount = _smsConsentResolved && _smsAutoImportEnabled
          ? await _autoImportSafeCandidates(
              candidates: _inbox
                  .where((item) => item.status == 'pending')
                  .toList(growable: false),
              notifyCandidateIds:
                  affectedCandidates.map((item) => item.id).toSet(),
            )
          : await _autoImportSafeCandidates(
              candidates: affectedCandidates,
              notifyCandidateIds:
                  affectedCandidates.map((item) => item.id).toSet(),
            );
      final reviewCount = _inbox
          .where((item) =>
              item.status == 'pending' && _isActionableSmsCandidate(item))
          .length;
      _setSmsStatus(
        _smsConsentResolved && _smsAutoImportEnabled
            ? 'SMS scan complete: ${result.insertedCount} new, $importedCount auto-imported, $reviewCount need review.'
            : 'SMS scan complete: ${result.insertedCount} new messages parsed; auto-import is off. Enable it to add clear transactions.',
      );
      return result.insertedCount;
    } catch (error, stackTrace) {
      debugPrint('SMS scan failed: $error\n$stackTrace');
      _setSmsStatus(
        error.toString().toLowerCase().contains('database is locked')
            ? 'The local database is busy. Wait a few seconds, then retry the SMS scan.'
            : 'SMS scan failed. Check access and try scanning again.',
        isError: true,
      );
      rethrow;
    } finally {
      _scanning = false;
      _smsLoadingLoaded = _smsLoadingTotal;
      notifyListeners();
    }
  }

  Future<int> _autoImportSafeCandidates({
    List<SmsInboxItem>? candidates,
    Set<String>? notifyCandidateIds,
  }) async {
    var importedCount = 0;
    if (!_smsConsentResolved || !_smsAutoImportEnabled) {
      for (final item
          in (candidates ?? _inbox.where((item) => item.status == 'pending'))) {
        if (!_isActionableSmsCandidate(item)) continue;
        final rule = _matcher.matchRule(item, _rules);
        final accountId = _candidateAccountId(item, rule);
        final reviewReason = accountId == null
            ? 'Account not mapped to sender'
            : 'First-run SMS import consent is required';
        if (accountId == null) {
          await _setCandidateReviewReason(item, reviewReason);
        }
        if (notifyCandidateIds == null ||
            notifyCandidateIds.contains(item.id)) {
          await _notificationGateway?.notifyVerificationRequired(
            inboxId: item.id,
            reason: reviewReason,
          );
        }
      }
      return importedCount;
    }
    const policy = SmsImportPolicy();
    final selected = candidates ??
        _inbox
            .where((item) => item.status == 'pending')
            .toList(growable: false);
    for (final item in selected.where((item) => item.status == 'pending')) {
      final rule = _matcher.matchRule(item, _rules);
      final hasSpecificRule = rule?.merchantPattern?.trim().isNotEmpty ?? false;
      final type = hasSpecificRule
          ? rule!.transactionType
          : item.parsedType != null
              ? _matcher.typeFromParsed(item.parsedType)
              : rule?.transactionType ?? 'expense';
      final accountId = _candidateAccountId(item, rule);
      final categoryId = _ruleCategoryMatchesType(rule, type)
          ? rule!.categoryId
          : _matcher.defaultCategoryId(
              type,
              _ledgerContext.categoryIds,
              _ledgerContext.categoryTypes,
              _ledgerContext.categoryIsSystem,
              categoryNames: _ledgerContext.categoryNames,
              description: item.body,
            );
      final toAccountId = type == 'transfer'
          ? _automaticTransferDestination(item, accountId)
          : null;
      final decision = policy.decide(
        mode: SmsImportMode.balanced,
        parsedType: type,
        amountMinorUnits: item.parsedAmountMinorUnits,
        currency: item.parsedCurrency,
        confidence: item.confidence,
        accountId: accountId,
        categoryId: categoryId,
        toAccountId: toAccountId,
      );
      if (!decision.shouldAutoImport) {
        final reviewReason =
            accountId == null && _isActionableSmsCandidate(item)
                ? 'Account not mapped to sender'
                : decision.reason;
        if (item.reviewReason != reviewReason) {
          await _setCandidateReviewReason(item, reviewReason);
        }
        if (_isActionableSmsCandidate(item) &&
            (notifyCandidateIds == null ||
                notifyCandidateIds.contains(item.id))) {
          await _notificationGateway?.notifyVerificationRequired(
            inboxId: item.id,
            reason: reviewReason,
          );
        }
        continue;
      }
      final txId = await importSmsCandidate(
        item.id,
        type: type,
        accountId: accountId,
        toAccountId: toAccountId,
        categoryId: categoryId,
      );
      if (txId == null) {
        await _notificationGateway?.notifyImportFailed(
          inboxId: item.id,
          reason: 'The transaction was valid but could not be saved',
        );
      } else {
        importedCount++;
      }
    }
    return importedCount;
  }

  bool _isActionableSmsCandidate(SmsInboxItem item) {
    if (item.parsedType != null || item.parsedAmountMinorUnits != null) {
      return true;
    }
    return item.reviewReason != 'noRoute' ||
        SmsKindClassifier.classify(item.body) == SmsKind.transactional;
  }

  String? _candidateAccountId(SmsInboxItem item, SmsRule? rule) {
    final hasSpecificRule = rule?.merchantPattern?.trim().isNotEmpty ?? false;
    final accountId = hasSpecificRule
        ? rule!.accountId
        : _mappedAccountId(item) ?? rule?.accountId;
    if (accountId == null ||
        accountId.trim().isEmpty ||
        !_ledgerContext.accountIds.contains(accountId)) {
      return null;
    }
    return accountId;
  }

  Future<void> _setCandidateReviewReason(
    SmsInboxItem item,
    String reason,
  ) async {
    if (item.reviewReason == reason) return;
    final updated = item.copyWith(reviewReason: reason);
    await _inboxRepo.update(updated);
    _inbox = _inbox
        .map((candidate) => candidate.id == item.id ? updated : candidate)
        .toList();
  }

  String? _mappedAccountId(SmsInboxItem item) {
    final accountType = _suggestedAccountType(item.senderId, item.body);
    for (final mapping in _senderAccountMappings) {
      if (mapping.senderId != item.senderId ||
          mapping.accountType != accountType) {
        continue;
      }
      final ids = _ledgerContext.accountIds;
      final types = _ledgerContext.accountTypes;
      final index = ids.indexOf(mapping.accountId);
      if (index >= 0 &&
          index < types.length &&
          _compatibleAccountTypes(accountType, types[index])) {
        return mapping.accountId;
      }
      return null;
    }
    return null;
  }

  bool _ruleCategoryMatchesType(SmsRule? rule, String type) {
    if (rule == null) return false;
    if (type == 'transfer') return rule.categoryId == 'sys_transfer';
    final categoryIndex = _ledgerContext.categoryIds.indexOf(rule.categoryId);
    return categoryIndex >= 0 &&
        categoryIndex < _ledgerContext.categoryTypes.length &&
        _ledgerContext.categoryTypes[categoryIndex] == type;
  }

  Future<int> mapSmsSendersToAccount({
    required List<String> senderIds,
    required String accountType,
    required String accountId,
  }) async {
    final cleanedSenderIds = senderIds
        .map((sender) => sender.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final accountIndex = _ledgerContext.accountIds.indexOf(accountId);
    if (cleanedSenderIds.isEmpty ||
        accountIndex < 0 ||
        accountIndex >= _ledgerContext.accountTypes.length ||
        !_compatibleAccountTypes(
          accountType,
          _ledgerContext.accountTypes[accountIndex],
        )) {
      throw ArgumentError(
          'The SMS sender mapping does not match this account.');
    }

    await _gate.run(() async {
      for (final senderId in cleanedSenderIds) {
        final mapping = SmsSenderAccountMapping(
          senderId: senderId,
          accountType: accountType,
          accountId: accountId,
          createdAt: _clock.now(),
        );
        await _senderAccountMappingRepo.upsert(mapping);
        _senderAccountMappings = [
          ..._senderAccountMappings.where((existing) =>
              existing.senderId != senderId ||
              existing.accountType != accountType),
          mapping,
        ];
      }
    });

    final pending = _inbox
        .where((item) =>
            item.status == 'pending' &&
            cleanedSenderIds.contains(item.senderId) &&
            _suggestedAccountType(item.senderId, item.body) == accountType)
        .toList(growable: false);
    var importedCount = 0;
    if (_smsConsentResolved && _smsAutoImportEnabled && pending.isNotEmpty) {
      importedCount = await _autoImportSafeCandidates(candidates: pending);
    }
    final reviewCount = pending
        .where((item) => _inbox.any(
            (updated) => updated.id == item.id && updated.status == 'pending'))
        .length;
    _setSmsStatus(
      _smsConsentResolved && _smsAutoImportEnabled
          ? 'Mapped ${cleanedSenderIds.length} SMS sender(s) to the account. $importedCount imported; $reviewCount need review.'
          : 'Mapped ${cleanedSenderIds.length} SMS sender(s) to the account. Enable auto-import to import clear transactions.',
    );
    notifyListeners();
    return importedCount;
  }

  String? _automaticTransferDestination(
    SmsInboxItem item,
    String? sourceAccountId,
  ) {
    if (sourceAccountId == null || sourceAccountId.isEmpty) return null;
    final ids = _ledgerContext.accountIds;
    final names = _ledgerContext.accountNames;
    final bodyIdentity = _accountSuggestionIdentity(item.body);
    final matches = <String>[];
    for (var i = 0; i < ids.length && i < names.length; i++) {
      if (ids[i] == sourceAccountId) continue;
      final identity = _accountSuggestionIdentity(names[i]);
      if (identity.length >= 4 && bodyIdentity.contains(identity)) {
        matches.add(ids[i]);
      }
    }
    if (matches.length == 1) return matches.single;
    return null;
  }

  // ── Import ─────────────────────────────────────────────────────────────
  /// Imports a pending candidate as a transaction. Returns the created
  /// transaction id, or null if the import was rejected.
  Future<String?> importSmsCandidate(
    String inboxId, {
    String? type,
    double? amount,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? description,
    DateTime? date,
  }) async {
    final import = ImportSmsCandidate(
      inboxRepo: _inboxRepo,
      ruleRepo: _ruleRepo,
      ledger: _ledger,
      gate: _gate,
      clock: _clock,
      uuid: _uuid,
      matcher: _matcher,
    );
    final result = await import(
      inboxId,
      inbox: _inbox,
      rules: _rules,
      accountIds: _ledgerContext.accountIds,
      accountTypes: _ledgerContext.accountTypes,
      categoryIds: _ledgerContext.categoryIds,
      categoryTypes: _ledgerContext.categoryTypes,
      categoryIsSystem: _ledgerContext.categoryIsSystem,
      categoryNames: _ledgerContext.categoryNames,
      type: type,
      amount: amount,
      accountId: accountId,
      toAccountId: toAccountId,
      categoryId: categoryId,
      description: description,
      date: date,
    );
    if (result == null) return null;
    _inbox =
        _inbox.map((i) => i.id == inboxId ? result.updatedItem : i).toList();
    _rules = await _ruleRepo.getAll();
    await _notificationGateway?.notifyImported(
      inboxId: inboxId,
      description:
          result.updatedItem.parsedMerchant ?? result.updatedItem.senderId,
    );
    notifyListeners();
    return result.txId;
  }

  // ── Inbox status ───────────────────────────────────────────────────────
  Future<void> dismissSmsCandidate(String inboxId) async {
    final decline = DeclineSmsMessage(inboxRepo: _inboxRepo, gate: _gate);
    final updated = await decline(inboxId, inbox: _inbox);
    if (updated == null) return;
    _inbox = _inbox.map((i) => i.id == inboxId ? updated : i).toList();
    notifyListeners();
  }

  Future<void> restoreSmsCandidate(String inboxId) async {
    final restore = RestoreSmsCandidate(inboxRepo: _inboxRepo, gate: _gate);
    final updated = await restore(inboxId, inbox: _inbox);
    if (updated == null) return;
    _inbox = _inbox.map((i) => i.id == inboxId ? updated : i).toList();
    notifyListeners();
  }

  Future<void> deleteSmsCandidate(String inboxId) async {
    final delete = DeleteSmsCandidate(inboxRepo: _inboxRepo, gate: _gate);
    await delete(inboxId);
    _inbox = _inbox.where((i) => i.id != inboxId).toList();
    notifyListeners();
  }

  // ── Rules ──────────────────────────────────────────────────────────────
  Future<void> saveSmsRule({
    required String senderId,
    String? merchantPattern,
    required String accountId,
    required String categoryId,
    required String transactionType,
  }) async {
    final save = SaveSmsRule(
      ruleRepo: _ruleRepo,
      gate: _gate,
      clock: _clock,
      uuid: _uuid,
    );
    _rules = await save(
      senderId: senderId,
      merchantPattern: merchantPattern ?? '',
      accountId: accountId,
      categoryId: categoryId,
      transactionType: transactionType,
      rules: _rules,
    );
    notifyListeners();
  }

  Future<void> deleteSmsRule(String id) async {
    final delete = DeleteSmsRule(ruleRepo: _ruleRepo, gate: _gate);
    await delete(id);
    _rules = _rules.where((r) => r.id != id).toList();
    notifyListeners();
  }

  /// Returns the rule that matches [item], if any.
  SmsRule? smsRuleForItem(SmsInboxItem item) =>
      _matcher.matchRule(item, _rules);

  Future<SmsVerification?> submitSmsVerification(
    String inboxId,
    Map<String, dynamic> corrections,
  ) async {
    final verificationRepo = _verificationRepo;
    final outboxRepo = _outboxRepo;
    if (verificationRepo == null || outboxRepo == null) return null;

    SmsInboxItem? item;
    for (final candidate in _inbox) {
      if (candidate.id == inboxId) {
        item = candidate;
        break;
      }
    }
    if (item == null) return null;

    final submit = SubmitSmsVerification(
      verificationRepo: verificationRepo,
      outboxRepo: outboxRepo,
      gate: _gate,
      clock: _clock,
      uuid: _uuid,
    );
    final verification = await submit(
      inboxId: item.id,
      senderId: item.senderId,
      rawHash: item.rawHash,
      body: item.body,
      corrections: corrections,
    );
    notifyListeners();
    return verification;
  }

  Future<SmsLearningProposal?> applySmsVerification(
    String verificationId, {
    int activationThreshold = 3,
  }) async {
    final verificationRepo = _verificationRepo;
    final outboxRepo = _outboxRepo;
    if (verificationRepo == null || outboxRepo == null) return null;

    final apply = ApplySmsVerification(
      verificationRepo: verificationRepo,
      outboxRepo: outboxRepo,
      gate: _gate,
      clock: _clock,
      uuid: _uuid,
    );
    final proposal = await apply(
      verificationId: verificationId,
      activationThreshold: activationThreshold,
    );
    _learningProposals =
        await verificationRepo.getLearningProposals(status: 'active');
    notifyListeners();
    return proposal;
  }

  // ── Sender preferences ─────────────────────────────────────────────────
  Future<void> setSmsSenderParseAllowed(String senderId, bool allowed) async {
    final id = senderId.trim();
    if (id.isEmpty) return;
    final set = SetSmsSenderParseAllowed(
      prefRepo: _prefRepo,
      gate: _gate,
      clock: _clock,
      uuid: _uuid,
    );
    _prefs = await set(id, allowed, prefs: _prefs);
    if (!allowed) {
      // Dismissing the sender also dismisses all its pending inbox items.
      final decline = DeclineSmsMessage(inboxRepo: _inboxRepo, gate: _gate);
      for (final item in _inbox) {
        if (item.senderId == id && item.status == 'pending') {
          final updated = await decline(item.id, inbox: _inbox);
          if (updated != null) {
            _inbox = _inbox.map((i) => i.id == item.id ? updated : i).toList();
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> suppressSmsKind(String senderId, String kind) async {
    final id = senderId.trim();
    if (id.isEmpty) return;
    final suppress = SuppressSmsKind(
      prefRepo: _prefRepo,
      gate: _gate,
      clock: _clock,
      uuid: _uuid,
    );
    _prefs = await suppress(id, kind, prefs: _prefs);
    notifyListeners();
  }

  Future<void> unsuppressSmsKind(String senderId, String kind) async {
    final id = senderId.trim();
    if (id.isEmpty) return;
    final unsuppress = UnsuppressSmsKind(prefRepo: _prefRepo, gate: _gate);
    _prefs = await unsuppress(id, kind, prefs: _prefs);
    notifyListeners();
  }

  Future<void> resetSmsSenderPrefs(String senderId) async {
    final id = senderId.trim();
    if (id.isEmpty) return;
    final reset = ResetSmsSenderPrefs(prefRepo: _prefRepo, gate: _gate);
    _prefs = await reset(id, prefs: _prefs);
    notifyListeners();
  }

  SmsSenderPref? smsSenderPref(String senderId) {
    for (final p in _prefs) {
      if (p.senderId == senderId) return p;
    }
    return null;
  }

  bool isSmsSenderParseAllowed(String senderId) {
    final pref = smsSenderPref(senderId);
    return pref == null || pref.parseAllowed;
  }

  bool isSmsKindSuppressed(String senderId, String kind) =>
      smsSenderPref(senderId)?.suppressedKinds.contains(kind) ?? false;

  // ── Auto-hide OTP ──────────────────────────────────────────────────────
  Future<void> setSmsAutoHideOtp(bool enabled) async {
    final set = SetSmsAutoHideOtp(settings: _settings, gate: _gate);
    _autoHideOtp = await set(enabled);
    notifyListeners();
  }

  Future<void> setFirstRunSmsImportConsent({
    required bool resolved,
    required bool autoImportEnabled,
  }) async {
    await _settings.setFirstRunSmsConsentResolved(resolved);
    await _settings.setSmsAutoImportEnabled(autoImportEnabled);
    _smsConsentResolved = resolved;
    _smsAutoImportEnabled = autoImportEnabled;
    if (resolved && autoImportEnabled) {
      await _autoImportSafeCandidates();
    }
    notifyListeners();
  }

  // ── Live capture ───────────────────────────────────────────────────────
  Future<void> startSmsLiveCapture() async {
    if (_live != null) return;
    await _settings.setLiveCaptureEnabled(true);
    _liveCaptureEnabled = true;
    final registry = _registry ?? await _registryProvider.load();
    _live = LiveCaptureController(
      source: _source,
      pipeline: SmsInboxPipeline(registry),
      inboxRepo: _inboxRepo,
      gate: _gate,
      isSenderAllowed: isSmsSenderParseAllowed,
      isKindSuppressed: isSmsKindSuppressed,
      autoHideOtp: () => _autoHideOtp,
      defaultCurrency: () => _ledgerContext.defaultCurrency,
      learningProposals: () => _learningProposals,
      onInserted: (item) async {
        _inbox = [item, ..._inbox];
        await _autoImportSafeCandidates(candidates: [item]);
        notifyListeners();
      },
    );
    try {
      await _live!.start();
    } catch (_) {
      _live = null;
      _liveCaptureEnabled = false;
      await _settings.setLiveCaptureEnabled(false);
      _setSmsStatus(
        'Live SMS capture could not start. You can scan the inbox manually.',
        isError: true,
      );
      rethrow;
    }
    notifyListeners();
  }

  Future<bool> _tryStartLiveCapture() async {
    try {
      await startSmsLiveCapture();
      return true;
    } catch (error, stackTrace) {
      debugPrint('SMS live capture failed to start: $error\n$stackTrace');
      return false;
    }
  }

  Future<void> stopSmsLiveCapture() async {
    await _live?.stop();
    _live = null;
    await _settings.setLiveCaptureEnabled(false);
    _liveCaptureEnabled = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _live?.stop();
    super.dispose();
  }
}
