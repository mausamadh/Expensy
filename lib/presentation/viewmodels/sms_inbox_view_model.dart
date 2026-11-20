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
  List<SmsAccountSuggestion> get smsAccountSuggestions {
    final grouped = <String, _SmsSuggestionAccumulator>{};
    for (final item in _inbox.where((item) => item.status == 'pending')) {
      final body = item.body.toLowerCase();
      final sender = item.senderId.trim();
      if (sender.isEmpty) continue;
      final key = sender.toUpperCase();
      final acc = grouped.putIfAbsent(
        key,
        () => _SmsSuggestionAccumulator(
          name: _suggestedAccountName(sender),
          type: _suggestedAccountType(sender, body),
          senderId: sender,
        ),
      );
      acc.evidenceCount++;
    }
    return grouped.values
        .map((acc) => SmsAccountSuggestion(
              name: acc.name,
              type: acc.type,
              senderId: acc.senderId,
              evidenceCount: acc.evidenceCount,
            ))
        .toList()
      ..sort((a, b) => b.evidenceCount.compareTo(a.evidenceCount));
  }

  String _suggestedAccountName(String sender) {
    final upper = sender.toUpperCase();
    const known = <String, String>{
      'CTZN_ALERT': 'Citizens Bank',
      'CTZNS_ALERT': 'Citizens Bank',
      'NABIL_ALERT': 'Nabil Bank',
      'NBL_ALERT': 'Nepal Bank',
      'NBLALERT': 'Nepal Bank',
      'LAXMI_ALERT': 'Laxmi Sunrise',
      'LAXMIALERT': 'Laxmi Sunrise',
      'SBL_ALERT': 'Siddhartha Bank',
      'SSF': 'Social Security Fund',
      'CIT': 'CIT Retirement Fund',
      'CIT_ALERT': 'CIT Retirement Fund',
      'KHALTI': 'Khalti Wallet',
      'ESEWA_ALERT': 'eSewa Wallet',
      'IME_ALERT': 'IME Pay',
    };
    return known[upper] ?? sender;
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

      await scanSmsInbox(limit: 5000);
      if (_liveCaptureEnabled && permissions.receive) {
        await startSmsLiveCapture();
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
  }) async {
    final perms = await _source.requestPermissions();
    _permissions = perms;
    notifyListeners();
    if (perms.canScan && scanOnGrant) {
      await scanSmsInbox(limit: 5000);
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
  Future<int> scanSmsInbox({int limit = 5000}) async {
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
        senderPrefs: {for (final p in _prefs) p.senderId: p},
        autoHideOtp: _autoHideOtp,
        defaultCurrency: _ledgerContext.defaultCurrency,
        learningProposals: _learningProposals,
        onMessagesLoaded: (total) {
          _smsLoadingTotal = total;
          notifyListeners();
        },
      );
      _inbox = await _inboxRepo.getAll();
      final refreshedIds = result.refreshedItemIds.toSet();
      final affectedCandidates = _inbox
          .where((item) =>
              !previousIds.contains(item.id) || refreshedIds.contains(item.id))
          .toList(growable: false);
      if (affectedCandidates.isNotEmpty) {
        await _autoImportSafeCandidates(candidates: affectedCandidates);
      }
      _setSmsStatus(
        result.insertedCount == 0
            ? result.refreshedItemIds.isEmpty
                ? 'SMS scan complete. No new messages were found; existing candidates remain in SMS Inbox.'
                : 'SMS scan complete. Refreshed ${result.refreshedItemIds.length} existing candidates.'
            : _smsConsentResolved && _smsAutoImportEnabled
                ? 'SMS scan complete. Processed ${result.insertedCount} new messages.'
                : 'SMS scan complete. Processed ${result.insertedCount} new messages; review them in SMS Inbox.',
      );
      return result.insertedCount;
    } catch (error, stackTrace) {
      debugPrint('SMS scan failed: $error\n$stackTrace');
      _setSmsStatus(
        'SMS scan failed. Check access and try scanning again.',
        isError: true,
      );
      rethrow;
    } finally {
      _scanning = false;
      _smsLoadingLoaded = _smsLoadingTotal;
      notifyListeners();
    }
  }

  Future<void> _autoImportSafeCandidates(
      {List<SmsInboxItem>? candidates}) async {
    if (!_smsConsentResolved || !_smsAutoImportEnabled) {
      for (final item
          in (candidates ?? _inbox.where((item) => item.status == 'pending'))) {
        await _notificationGateway?.notifyVerificationRequired(
          inboxId: item.id,
          reason: 'First-run SMS import consent is required',
        );
      }
      return;
    }
    const policy = SmsImportPolicy();
    final selected = candidates ??
        _inbox
            .where((item) => item.status == 'pending')
            .toList(growable: false);
    for (final item in selected.where((item) => item.status == 'pending')) {
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
      if (!decision.shouldAutoImport) {
        await _notificationGateway?.notifyVerificationRequired(
          inboxId: item.id,
          reason: decision.reason,
        );
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
      }
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

class _SmsSuggestionAccumulator {
  _SmsSuggestionAccumulator({
    required this.name,
    required this.type,
    required this.senderId,
  });

  final String name;
  final String type;
  final String senderId;
  int evidenceCount = 0;
}
