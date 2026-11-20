import 'package:flutter/foundation.dart';

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/application/sms_import/sms_import_use_cases.dart';
import 'package:finwick/domain/shared/clock.dart';
import 'package:finwick/domain/shared/uuid.dart';
import 'package:finwick/domain/sms_import/sms_entities.dart';
import 'package:finwick/domain/sms_import/sms_inbox_pipeline.dart';
import 'package:finwick/domain/sms_import/sms_rule_matcher.dart';
import 'package:finwick/domain/sms_import/sms_verification.dart';
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
  bool _scanning = false;
  bool _autoHideOtp = true;
  bool _liveCaptureEnabled = false;
  List<SmsLearningProposal> _learningProposals = [];
  SmsPermissions? _permissions;
  TemplateRegistry? _registry;
  LiveCaptureController? _live;

  // ── State getters ──────────────────────────────────────────────────────
  List<SmsInboxItem> get smsInbox => _inbox;
  List<SmsRule> get smsRules => _rules;
  List<SmsSenderPref> get smsSenderPrefs => _prefs;
  bool get smsScanning => _scanning;
  bool get smsAutoHideOtp => _autoHideOtp;
  bool get smsLiveCaptureEnabled => _liveCaptureEnabled;
  List<SmsLearningProposal> get smsLearningProposals => _learningProposals;
  SmsPermissions? get smsPermissions => _permissions;

  // ── Load ───────────────────────────────────────────────────────────────
  /// Loads the initial state from the repositories and settings.
  Future<void> load() async {
    _inbox = await _inboxRepo.getAll();
    _rules = await _ruleRepo.getAll();
    _prefs = await _prefRepo.getAll();
    _autoHideOtp = await _settings.getAutoHideOtp();
    _liveCaptureEnabled = await _settings.getLiveCaptureEnabled();
    _learningProposals =
        await (_verificationRepo?.getLearningProposals(status: 'active') ??
            Future<List<SmsLearningProposal>>.value(const []));
    _registry = await _registryProvider.load();
    notifyListeners();
  }

  // ── Permissions ────────────────────────────────────────────────────────
  Future<SmsPermissions> checkSmsPermissions() async {
    final perms = await _source.checkPermissions();
    _permissions = perms;
    notifyListeners();
    return perms;
  }

  Future<SmsPermissions> requestSmsPermissions() async {
    final perms = await _source.requestPermissions();
    _permissions = perms;
    notifyListeners();
    return perms;
  }

  // ── Senders ────────────────────────────────────────────────────────────
  Future<List<SmsSender>> getSmsSenders() => _source.getSenders();

  // ── Scan ───────────────────────────────────────────────────────────────
  Future<int> scanSmsInbox({int limit = 500}) async {
    if (_scanning) return 0;
    _scanning = true;
    notifyListeners();
    try {
      final registry = _registry ?? await _registryProvider.load();
      final scan = ScanSmsInbox(
        source: _source,
        inboxRepo: _inboxRepo,
        registry: registry,
        gate: _gate,
      );
      final inserted = await scan(
        limit: limit,
        senderPrefs: {for (final p in _prefs) p.senderId: p},
        autoHideOtp: _autoHideOtp,
        defaultCurrency: _ledgerContext.defaultCurrency,
        learningProposals: _learningProposals,
      );
      if (inserted > 0) {
        _inbox = await _inboxRepo.getAll();
        await _autoImportSafeCandidates();
      }
      return inserted;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> _autoImportSafeCandidates() async {
    const policy = SmsImportPolicy();
    final candidates = _inbox
        .where((item) => item.status == 'pending')
        .toList(growable: false);
    for (final item in candidates) {
      final rule = _matcher.matchRule(item, _rules);
      final type =
          rule?.transactionType ?? _matcher.typeFromParsed(item.parsedType);
      final accountId = rule?.accountId ??
          _matcher.defaultAccountId(
              _ledgerContext.accountIds, _ledgerContext.accountTypes);
      final categoryId = rule?.categoryId ??
          _matcher.defaultCategoryId(
            type,
            _ledgerContext.categoryIds,
            _ledgerContext.categoryTypes,
            _ledgerContext.categoryIsSystem,
          );
      final toAccountId = type == 'transfer'
          ? _matcher.transferToAccount(
              accountId,
              _ledgerContext.accountIds,
            )
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
      if (!decision.shouldAutoImport) continue;
      await importSmsCandidate(
        item.id,
        type: type,
        accountId: accountId,
        toAccountId: toAccountId,
        categoryId: categoryId,
      );
    }
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
        if (item.confidence != 'high') {
          _notificationGateway?.notifyVerificationRequired(
            inboxId: item.id,
            reason: item.reviewReason ?? 'The SMS could not be parsed safely',
          );
        } else {
          await _autoImportSafeCandidates();
        }
        notifyListeners();
      },
    );
    await _live!.start();
    notifyListeners();
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
