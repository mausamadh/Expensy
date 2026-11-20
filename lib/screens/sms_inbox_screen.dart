// lib/screens/sms_inbox_screen.dart
// SMS transaction inbox: scans the device inbox, lists parsed candidates, and
// lets the user verify/edit each one before it is committed to the ledger.
// All state mutations route through AppProvider (UI-DB decoupling).
import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../presentation/viewmodels/categories_view_model.dart';
import 'accounts_screen.dart';
import '../domain/sms_import/sms_parser.dart';
import '../presentation/viewmodels/sms_inbox_view_model.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../utils/snackbar.dart';
import '../widgets/fintech_components.dart';
import '../widgets/shared_widgets.dart';

// ── class SmsInboxScreen ─────────────────────────────────────────────────────
// Encapsulates UI state and rendering logic for SmsInboxScreen.
class SmsInboxScreen extends StatefulWidget {
  const SmsInboxScreen({super.key});

  @override
  State<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends State<SmsInboxScreen> {
  bool _live = false;

  /// Active inbox filters (UI-only; they never touch the DB).
  /// `_senderFilter` is a sender id, or null for "all senders".
  /// `_dateFilter` is a preset key, or null for "all time".
  String? _senderFilter;
  String? _dateFilter;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Applies the active sender + date filters to [pending].
  List<SmsInboxItem> _filtered(List<SmsInboxItem> pending) {
    var items = pending;
    if (_senderFilter != null) {
      items = items.where((i) => i.senderId == _senderFilter).toList();
    }
    if (_dateFilter != null) {
      final now = DateTime.now();
      final cutoff = switch (_dateFilter) {
        'today' => DateTime(now.year, now.month, now.day),
        'week' => now.subtract(const Duration(days: 7)),
        'month' => now.subtract(const Duration(days: 30)),
        _ => null,
      };
      if (cutoff != null) {
        items = items.where((i) {
          final d = i.parsedDate ??
              (i.smsTimestamp > 0
                  ? DateTime.fromMillisecondsSinceEpoch(i.smsTimestamp)
                  : null);
          return d != null && !d.isBefore(cutoff);
        }).toList();
      }
    }
    return items;
  }

  Future<void> _bootstrap() async {
    final vm = context.read<SmsInboxViewModel>();
    await vm.load();
    await vm.checkSmsPermissions();
    _live = vm.smsLiveCaptureEnabled;
    if (mounted) setState(() {});
  }

  Future<void> _scan() async {
    final vm = context.read<SmsInboxViewModel>();
    final added = await vm.scanSmsInbox(limit: 5000);
    if (!mounted) return;
    showAppSnackbar(
      context,
      added > 0
          ? 'Found $added new transaction(s)'
          : 'No new transactions found',
    );
  }

  Future<void> _toggleLive() async {
    final vm = context.read<SmsInboxViewModel>();
    if (_live) {
      await vm.stopSmsLiveCapture();
    } else {
      await vm.startSmsLiveCapture();
    }
    if (mounted) setState(() => _live = !_live);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vm = context.watch<SmsInboxViewModel>();
    final perms = vm.smsPermissions;
    final pending = vm.smsInbox.where((i) => i.status == 'pending').toList()
      ..sort((a, b) => b.smsTimestamp.compareTo(a.smsTimestamp));
    final filtered = _filtered(pending);
    // Derive senders from ALL inbox items (not just pending) so the sender
    // filter dropdown stays valid after the last pending item of a sender is
    // imported/dismissed — otherwise the DropdownButtonFormField assertion
    // fires (value not in items) and the screen goes red.
    final senders = vm.smsInbox
        .map((i) => i.senderId)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            FintechHeader(
              title: 'SMS Inbox',
              subtitle: 'Auto-detect transactions from your messages',
              actions: [
                FintechCircleButton(
                  icon: Icons.manage_search_rounded,
                  tooltip: 'Scan inbox',
                  onTap: () {
                    AppHaptics.tap(context, HapticStrength.light);
                    _scan();
                  },
                ),
                const SizedBox(width: 8),
                FintechCircleButton(
                  icon: _live ? Icons.stop_circle_rounded : Icons.radar_rounded,
                  tooltip: _live ? 'Stop live capture' : 'Live capture',
                  onTap: () {
                    AppHaptics.tap(context, HapticStrength.light);
                    _toggleLive();
                  },
                ),
                const SizedBox(width: 8),
                FintechCircleButton(
                  icon: Icons.rule_rounded,
                  tooltip: 'Rules & senders',
                  onTap: () {
                    AppHaptics.tap(context, HapticStrength.light);
                    _openRulesSheet(context);
                  },
                ),
              ],
            ),
            if (perms != null && !perms.canScan)
              _PermissionBanner(
                onGrant: () async {
                  await context
                      .read<SmsInboxViewModel>()
                      .requestSmsPermissions();
                  if (mounted) setState(() {});
                },
              ),
            if (_live)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: kSuccessColor.withValues(alpha: isDark ? 0.18 : 0.12),
                child: Row(
                  children: [
                    Icon(Icons.radar_rounded, size: 16, color: kSuccessColor),
                    const SizedBox(width: 8),
                    Text(
                      'Live capture on — new messages are parsed automatically',
                      style: TextStyle(fontSize: 12, color: kSuccessColor),
                    ),
                  ],
                ),
              ),
            if (vm.smsScanning)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: isDark ? 0.16 : 0.10),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        vm.smsLoadingTotal > 0
                            ? 'Loading SMS transactions: ${vm.smsLoadingTotal} messages'
                            : 'Loading SMS transactions...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (vm.smsAccountSuggestions.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: kWarningColor.withValues(alpha: isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: kWarningColor.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Accounts detected from SMS',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create or reconcile these accounts and enter their current balances.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final suggestion in vm.smsAccountSuggestions.take(4))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton.icon(
                          onPressed: () => AccountsScreen.openSheet(
                            context,
                            isCard: suggestion.type == 'credit',
                          ),
                          icon: Icon(
                            suggestion.type == 'credit'
                                ? Icons.credit_card_rounded
                                : suggestion.type == 'wallet'
                                    ? Icons.account_balance_wallet_rounded
                                    : Icons.account_balance_rounded,
                            size: 18,
                          ),
                          label: Text(
                            'Set up ${suggestion.name} (${suggestion.type})',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (pending.isNotEmpty)
              _FilterBar(
                senders: senders,
                senderFilter: _senderFilter,
                dateFilter: _dateFilter,
                onSenderChanged: (v) => setState(() => _senderFilter = v),
                onDateChanged: (v) => setState(() => _dateFilter = v),
                onClear: () => setState(() {
                  _senderFilter = null;
                  _dateFilter = null;
                }),
              ),
            Expanded(
              child: vm.smsScanning
                  ? const Center(child: CircularProgressIndicator())
                  : pending.isEmpty
                      ? _EmptyState(onScan: _scan)
                      : filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.filter_alt_off_rounded,
                                      size: 40,
                                      color: hairlineBorderColor(
                                        Theme.of(context).colorScheme,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No messages match the current filters',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: hairlineBorderColor(
                                          Theme.of(context).colorScheme,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _senderFilter = null;
                                        _dateFilter = null;
                                      }),
                                      child: const Text('Clear filters'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _scan,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, i) =>
                                    _CandidateCard(item: filtered[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRulesSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _RulesSheet(),
    );
  }
}

// ── Permission banner ────────────────────────────────────────────────────────
class _PermissionBanner extends StatelessWidget {
  final VoidCallback onGrant;
  const _PermissionBanner({required this.onGrant});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: kWarningColor.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: kWarningColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'SMS access is needed to read and parse your messages.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurface),
            ),
          ),
          FilledButton(
            onPressed: onGrant,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Grant', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────
// ── Filter bar (sender + date presets) ───────────────────────────────────────
class _FilterBar extends StatelessWidget {
  final List<String> senders;
  final String? senderFilter;
  final String? dateFilter;
  final ValueChanged<String?> onSenderChanged;
  final ValueChanged<String?> onDateChanged;
  final VoidCallback onClear;

  const _FilterBar({
    required this.senders,
    required this.senderFilter,
    required this.dateFilter,
    required this.onSenderChanged,
    required this.onDateChanged,
    required this.onClear,
  });

  static const _datePresets = <String, String>{
    'today': 'Today',
    'week': '7 days',
    'month': '30 days',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = senderFilter != null || dateFilter != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          // Sender dropdown
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('sender_$senderFilter'),
              initialValue: senderFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Sender',
                labelStyle: TextStyle(
                    fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All senders')),
                ...senders.map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child:
                        Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: (v) => onSenderChanged(v),
            ),
          ),
          const SizedBox(width: 8),
          // Date preset dropdown
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              key: ValueKey('date_$dateFilter'),
              initialValue: dateFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Date',
                labelStyle: TextStyle(
                    fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All time')),
                ..._datePresets.entries.map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                ),
              ],
              onChanged: (v) => onDateChanged(v),
            ),
          ),
          const SizedBox(width: 8),
          // Clear button
          if (active)
            IconButton(
              tooltip: 'Clear filters',
              icon: const Icon(Icons.filter_alt_off_rounded, size: 20),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onScan;
  const _EmptyState({required this.onScan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sms_rounded, size: 34, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'No pending transactions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scan your inbox to find transaction messages from banks, wallets, and merchants.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.manage_search_rounded),
              label: const Text('Scan inbox'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Candidate card ───────────────────────────────────────────────────────────
class _CandidateCard extends StatelessWidget {
  final SmsInboxItem item;
  const _CandidateCard({required this.item});

  Color _confidenceColor(String? c) {
    switch (c) {
      case 'high':
        return kSuccessColor;
      case 'medium':
        return kWarningColor;
      case 'low':
        return kWarningColor;
      default:
        return kDangerColor;
    }
  }

  IconData _typeIcon(String? t) {
    switch (t) {
      case 'income':
        return Icons.south_west_rounded;
      case 'transfer':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.north_east_rounded;
    }
  }

  Color _typeColor(String? t) {
    switch (t) {
      case 'income':
        return kSuccessColor;
      case 'transfer':
        return kCertificateColor;
      default:
        return kDangerColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final app = context.read<AppProvider>();
    final cur = item.parsedCurrency ?? app.settings.currency;
    final amount = item.parsedAmountMinorUnits != null
        ? item.parsedAmountMinorUnits! / math.pow(10, Iso4217.exponentFor(cur))
        : null;

    final date = item.parsedDate ??
        (item.smsTimestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(item.smsTimestamp)
            : null);

    return GestureDetector(
      onTap: () {
        AppHaptics.tap(context, HapticStrength.selection);
        _openVerifySheet(context, item);
      },
      onLongPress: () => _confirmDelete(context, item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainer.withValues(alpha: isDark ? 0.45 : 0.65),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _typeColor(item.parsedType)
                        .withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_typeIcon(item.parsedType),
                      size: 20, color: _typeColor(item.parsedType)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.parsedMerchant ?? item.senderId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.senderId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                ),
                if (amount != null)
                  Text(
                    (item.parsedType == 'income' ? '+' : '') +
                        formatAmount(amount, cur),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _typeColor(item.parsedType),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                StatusBadge(
                  label: (item.confidence ?? 'unknown').toUpperCase(),
                  color: _confidenceColor(item.confidence),
                  icon: Icons.verified_rounded,
                ),
                const SizedBox(width: 6),
                if (date != null)
                  Text(
                    DateFormat('d MMM yyyy').format(date),
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.55)),
                  ),
                const Spacer(),
                if (item.reviewReason != null && item.reviewReason!.isNotEmpty)
                  Flexible(
                    child: Text(
                      item.reviewReason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: kWarningColor),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _decline(context, item),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Decline'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 34),
                      foregroundColor: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    AppHaptics.tap(context, HapticStrength.selection);
                    _openVerifySheet(context, item);
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Verify'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 34),
                    foregroundColor: kSuccessColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _decline(BuildContext context, SmsInboxItem item) async {
    final vm = context.read<SmsInboxViewModel>();
    final sender = item.senderId;
    // Declines ONLY this message — the sender is not blocked, so its future
    // messages will still be parsed and shown as candidates.
    await vm.dismissSmsCandidate(item.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Declined this message only — ${sender.isEmpty ? 'sender' : sender} will still be parsed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => vm.restoreSmsCandidate(item.id),
        ),
      ),
    );
  }

  void _openVerifySheet(BuildContext context, SmsInboxItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SmsVerifySheet(item: item),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SmsInboxItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
            'This removes the candidate permanently. It cannot be recovered.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kDangerColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<SmsInboxViewModel>().deleteSmsCandidate(item.id);
    }
  }
}

// ── Verify / edit sheet ──────────────────────────────────────────────────────
class _SmsVerifySheet extends StatefulWidget {
  final SmsInboxItem item;
  const _SmsVerifySheet({required this.item});

  @override
  State<_SmsVerifySheet> createState() => _SmsVerifySheetState();
}

class _SmsVerifySheetState extends State<_SmsVerifySheet> {
  late String _type;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descCtrl;
  late String? _accountId;
  late String? _toAccountId;
  late String? _categoryId;
  late DateTime _date;

  /// Kind to suppress for this sender on dismiss (null = don't suppress).
  String? _dontShowAgain;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    final vm = context.read<SmsInboxViewModel>();
    final item = widget.item;

    // Pre-fill from a saved sender→account/category mapping, if any, so the
    // user doesn't have to re-select the account for a known sender.
    final rule = vm.smsRuleForItem(item);
    _type = rule?.transactionType ??
        (item.parsedType == 'income' || item.parsedType == 'transfer'
            ? item.parsedType!
            : 'expense');

    final cur = item.parsedCurrency ?? app.settings.currency;
    final major = item.parsedAmountMinorUnits != null
        ? item.parsedAmountMinorUnits! / math.pow(10, Iso4217.exponentFor(cur))
        : 0.0;
    _amountCtrl =
        TextEditingController(text: major > 0 ? major.toStringAsFixed(2) : '');
    _descCtrl = TextEditingController(text: _autoDescription(item));
    _date = item.parsedDate ??
        (item.smsTimestamp > 0
            ? DateTime.fromMillisecondsSinceEpoch(item.smsTimestamp)
            : DateTime.now());

    // Default account: the saved rule's account if it still exists, else the
    // first non-credit account.
    final accounts = app.accounts.where((a) => !a.isCredit).toList();
    final ruleAccount = rule?.accountId;
    _accountId =
        (ruleAccount != null && accounts.any((a) => a.id == ruleAccount))
            ? ruleAccount
            : (accounts.isNotEmpty ? accounts.first.id : null);

    // Default destination for transfers: first account that isn't the source.
    final toCandidates = accounts.where((a) => a.id != _accountId).toList();
    _toAccountId = toCandidates.isNotEmpty ? toCandidates.first.id : null;

    // Default category: the saved rule's category if it still exists, else the
    // first user category matching the type.
    final ruleCat = rule?.categoryId;
    final cats = app.userCategories.where((c) => c.type == _type).toList();
    _categoryId = _type == 'transfer'
        ? 'sys_transfer'
        : ((ruleCat != null && cats.any((c) => c.id == ruleCat))
            ? ruleCat
            : (cats.isNotEmpty ? cats.first.id : null));
  }

  /// Builds the auto-filled description from the SMS content: the parsed
  /// merchant when available, otherwise a cleaned snippet of the body, with
  /// the parsed reference appended as "(Ref: …)" when present.
  static String _autoDescription(SmsInboxItem item) {
    final merchant = (item.parsedMerchant ?? '').trim();
    String base;
    if (merchant.isNotEmpty) {
      base = merchant;
    } else {
      final body = item.body.replaceAll(RegExp(r'\s+'), ' ').trim();
      base = body.length > 80 ? '${body.substring(0, 77)}…' : body;
    }
    final ref = (item.parsedReference ?? '').trim();
    if (ref.isNotEmpty) {
      base = base.isEmpty ? 'Ref: $ref' : '$base (Ref: $ref)';
    }
    return base;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _onTypeChanged(String t) {
    setState(() {
      _type = t;
      if (t == 'transfer') {
        // Pick a sensible default destination (first account != source).
        final accounts = context
            .read<AppProvider>()
            .accounts
            .where((a) => !a.isCredit)
            .toList();
        final toCandidates = accounts.where((a) => a.id != _accountId).toList();
        _toAccountId = toCandidates.isNotEmpty ? toCandidates.first.id : null;
      } else {
        final cats = context
            .read<AppProvider>()
            .userCategories
            .where((c) => c.type == t)
            .toList();
        if (_categoryId == null ||
            (context.read<AppProvider>().categoryById(_categoryId!)?.type !=
                t)) {
          _categoryId = cats.isNotEmpty ? cats.first.id : null;
        }
      }
    });
  }

  /// Selects the source account, keeping the transfer destination distinct.
  void _onFromAccountChanged(String? id) {
    setState(() {
      _accountId = id;
      if (_type == 'transfer' && _toAccountId == id) {
        final accounts = context
            .read<AppProvider>()
            .accounts
            .where((a) => !a.isCredit)
            .toList();
        final toCandidates = accounts.where((a) => a.id != id).toList();
        _toAccountId = toCandidates.isNotEmpty ? toCandidates.first.id : null;
      }
    });
  }

  Future<void> _import() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0.0;
    if (amount <= 0) {
      showAppSnackbar(context, 'Enter a valid amount');
      return;
    }
    if (_accountId == null) {
      showAppSnackbar(context, 'Select an account');
      return;
    }
    if (_type != 'transfer' && _categoryId == null) {
      showAppSnackbar(context, 'Select a category');
      return;
    }
    if (_type == 'transfer' &&
        (_toAccountId == null || _toAccountId == _accountId)) {
      showAppSnackbar(context, 'Select a different destination account');
      return;
    }
    setState(() => _busy = true);
    final txId = await context.read<SmsInboxViewModel>().importSmsCandidate(
          widget.item.id,
          type: _type,
          amount: amount,
          accountId: _accountId,
          toAccountId: _type == 'transfer' ? _toAccountId : null,
          categoryId: _type == 'transfer' ? null : _categoryId,
          description: _descCtrl.text,
          date: _date,
        );
    if (!mounted) return;
    if (txId != null) {
      Navigator.pop(context);
      showAppSnackbar(context, 'Transaction added');
    } else {
      setState(() => _busy = false);
      showAppSnackbar(context, 'Could not import — check the fields');
    }
  }

  Future<void> _dismiss() async {
    final vm = context.read<SmsInboxViewModel>();
    if (_dontShowAgain != null) {
      await vm.suppressSmsKind(widget.item.senderId, _dontShowAgain!);
    }
    await vm.dismissSmsCandidate(widget.item.id);
    if (!mounted) return;
    Navigator.pop(context);
    if (_dontShowAgain != null) {
      showAppSnackbar(context,
          "Won't show ${_dontShowAgain} messages from ${widget.item.senderId} again");
    }
  }

  /// Saves a routing rule for this sender (using the selected account,
  /// category and type) without committing a transaction. Useful when the
  /// message is a possible transaction that the parser couldn't classify —
  /// the rule ensures future messages from this sender are routed correctly.
  Future<void> _saveRuleOnly() async {
    final vm = context.read<SmsInboxViewModel>();
    if (_accountId == null) {
      showAppSnackbar(context, 'Select an account first');
      return;
    }
    if (_type != 'transfer' && _categoryId == null) {
      showAppSnackbar(context, 'Select a category first');
      return;
    }
    setState(() => _busy = true);
    await vm.saveSmsRule(
      senderId: widget.item.senderId,
      merchantPattern: (widget.item.parsedMerchant ?? '').trim().isEmpty
          ? null
          : widget.item.parsedMerchant,
      accountId: _accountId!,
      categoryId: _type == 'transfer' ? 'sys_transfer' : _categoryId!,
      transactionType: _type,
    );
    await vm.dismissSmsCandidate(widget.item.id);
    if (!mounted) return;
    Navigator.pop(context);
    showAppSnackbar(context, 'Rule saved for ${widget.item.senderId}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    context.watch<CategoriesViewModel>();
    final cs = Theme.of(context).colorScheme;
    final cur = widget.item.parsedCurrency ?? app.settings.currency;
    final cats = app.userCategories.where((c) => c.type == _type).toList();
    final accounts = app.accounts.where((a) => !a.isCredit).toList();

    return SheetShell(
      title: 'Verify transaction',
      subtitle: widget.item.senderId,
      showHandle: true,
      children: [
        // ── Original SMS message ──────────────────────────────────────────
        if (widget.item.body.trim().isNotEmpty) ...[
          Text('SMS MESSAGE',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(letterSpacing: 1)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hairlineBorderColor(cs)),
            ),
            child: Text(
              widget.item.body,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontFamily: 'monospace',
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Type ──────────────────────────────────────────────────────────
        TypeToggleChips(
          selectedValue: _type,
          firstValue: 'expense',
          firstLabel: 'Expense',
          firstColor: kDangerColor,
          secondValue: 'income',
          secondLabel: 'Income',
          secondColor: kSuccessColor,
          thirdValue: 'transfer',
          thirdLabel: 'Transfer',
          thirdColor: kCertificateColor,
          onChanged: _onTypeChanged,
        ),
        const SizedBox(height: 16),

        // ── Amount ────────────────────────────────────────────────────────
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Amount ($cur)',
            prefixIcon: const Icon(Icons.payments_outlined),
          ),
        ),
        const SizedBox(height: 14),

        // ── Description / merchant ────────────────────────────────────────
        TextField(
          controller: _descCtrl,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description',
            prefixIcon: Icon(Icons.notes_outlined),
          ),
        ),
        const SizedBox(height: 14),

        // ── Account ───────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text('ACCOUNT',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(letterSpacing: 1)),
            ),
            TextButton.icon(
              onPressed: () => AccountsScreen.openSheet(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New account'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hairlineBorderColor(cs)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No accounts yet. Create one to map this sender to.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
          )
        else
          AccountCardPicker(
            accounts: accounts,
            selectedId: _accountId,
            onSelected: _onFromAccountChanged,
          ),
        const SizedBox(height: 14),

        // ── Destination account (transfers only) ──────────────────────────
        if (_type == 'transfer') ...[
          Text('TRANSFER TO',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(letterSpacing: 1)),
          const SizedBox(height: 8),
          AccountCardPicker(
            accounts: accounts,
            selectedId: _toAccountId,
            disabledId: _accountId,
            onSelected: (id) => setState(() => _toAccountId = id),
          ),
          const SizedBox(height: 14),
        ],

        // ── Category (not for transfers) ──────────────────────────────────
        if (_type != 'transfer') ...[
          Text('CATEGORY',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(letterSpacing: 1)),
          const SizedBox(height: 8),
          CategoryChipPicker(
            categories: cats,
            selectedId: _categoryId,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 14),
        ],

        // ── Date ──────────────────────────────────────────────────────────
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_outlined),
          title: Text(
            DateFormat('EEEE, d MMM yyyy').format(_date),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: () async {
            final p = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (p != null) setState(() => _date = p);
          },
        ),
        const SizedBox(height: 8),

        // ── Remembered mapping ────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.memory_rounded,
                size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Account & category are remembered for this sender — '
                'next time it will be pre-filled.',
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ── Don't show again (per-kind suppression) ───────────────────────
        Row(
          children: [
            Expanded(
              child: Text("DON'T SHOW AGAIN",
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(letterSpacing: 1)),
            ),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _dontShowAgain,
                isExpanded: true,
                decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Off')),
                  DropdownMenuItem(value: 'otp', child: Text('OTP / codes')),
                  DropdownMenuItem(
                      value: 'promotional', child: Text('Promotional')),
                  DropdownMenuItem(value: 'personal', child: Text('Personal')),
                ],
                onChanged: (v) => setState(() => _dontShowAgain = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Applies to future messages of this kind from '
          '${widget.item.senderId}. Transactions are never hidden.',
          style: TextStyle(
              fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 8),

        // ── Save rule only (for unclassified / possible transactions) ─────
        TextButton.icon(
          onPressed: _busy ? null : _saveRuleOnly,
          icon: const Icon(Icons.rule_rounded, size: 18),
          label: const Text('Save rule only (no transaction)'),
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: cs.primary,
          ),
        ),

        // ── Actions ───────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _dismiss,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Dismiss'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy ? null : _import,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Add transaction'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Rules & senders sheet ────────────────────────────────────────────────────
class _RulesSheet extends StatefulWidget {
  @override
  State<_RulesSheet> createState() => _RulesSheetState();
}

class _RulesSheetState extends State<_RulesSheet> {
  List<SmsSender> _senders = [];
  bool _loadingSenders = false;

  @override
  void initState() {
    super.initState();
    _loadSenders();
  }

  Future<void> _loadSenders() async {
    setState(() => _loadingSenders = true);
    final vm = context.read<SmsInboxViewModel>();
    try {
      final senders = await vm.getSmsSenders();
      if (mounted) setState(() => _senders = senders);
    } catch (_) {
      // Permission not granted or no messages — leave empty.
    } finally {
      if (mounted) setState(() => _loadingSenders = false);
    }
  }

  /// Opens a sheet to map a sender to an account (and optionally a category
  /// and type), creating a routing rule so future messages auto-import.
  void _mapSender(String sender) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SenderMapSheet(sender: sender),
    );
  }

  /// Opens the per-sender preferences sheet (parse allow/deny + per-kind
  /// suppression).
  void _openPrefSheet(String sender) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SenderPrefSheet(sender: sender),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final app = context.watch<AppProvider>();
    context.watch<CategoriesViewModel>();
    final vm = context.watch<SmsInboxViewModel>();
    final rules = vm.smsRules;

    return SheetShell(
      title: 'Rules & senders',
      showHandle: true,
      children: [
        // ── Global filters ────────────────────────────────────────────────
        Text('GLOBAL FILTERS',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(letterSpacing: 1)),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-hide OTPs',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'Verification codes are hidden automatically. Real transactions are never hidden.',
            style: TextStyle(fontSize: 11.5),
          ),
          value: vm.smsAutoHideOtp,
          onChanged: (v) => vm.setSmsAutoHideOtp(v),
        ),
        const SizedBox(height: 12),

        // ── Saved rules ───────────────────────────────────────────────────
        Text('SAVED RULES',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(letterSpacing: 1)),
        const SizedBox(height: 8),
        if (rules.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No rules yet. When you verify a transaction, tick "Remember this rule" to create one.',
              style: TextStyle(fontSize: 12.5),
            ),
          )
        else
          ...rules.map((r) => _RuleRow(
                rule: r,
                accountName: app.accountById(r.accountId)?.name ?? 'Unknown',
                categoryName: app.categoryById(r.categoryId)?.name ?? 'Unknown',
                onDelete: () async {
                  await vm.deleteSmsRule(r.id);
                },
              )),
        const SizedBox(height: 20),

        // ── Sender preferences ────────────────────────────────────────────
        Text('SENDER PREFERENCES',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(letterSpacing: 1)),
        const SizedBox(height: 8),
        if (vm.smsSenderPrefs.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No preferences yet. Dismiss a message with "Don\'t show again", or tap the settings icon on a sender below to control what gets parsed.',
              style: TextStyle(fontSize: 12.5),
            ),
          )
        else
          ...vm.smsSenderPrefs.map((p) => _SenderPrefRow(
                pref: p,
                onTap: () => _openPrefSheet(p.senderId),
              )),
        const SizedBox(height: 20),

        // ── Detected senders ──────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text('DETECTED SENDERS',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(letterSpacing: 1)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Refresh',
              onPressed: _loadingSenders ? null : _loadSenders,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingSenders)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_senders.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No senders detected. Grant SMS access and scan your inbox first.',
              style: TextStyle(fontSize: 12.5),
            ),
          )
        else
          ..._senders.map((s) {
            final rule = rules.firstWhereOrNull((r) => r.senderId == s.sender);
            final accountName =
                rule != null ? app.accountById(rule.accountId)?.name : null;
            return _SenderRow(
              sender: s.sender,
              count: s.count,
              mappedAccountName: accountName,
              onMap: () => _mapSender(s.sender),
              onPrefs: () => _openPrefSheet(s.sender),
            );
          }),
      ],
    );
  }
}

class _SenderRow extends StatelessWidget {
  final String sender;
  final int count;
  final String? mappedAccountName;
  final VoidCallback onMap;
  final VoidCallback onPrefs;
  const _SenderRow({
    required this.sender,
    required this.count,
    required this.mappedAccountName,
    required this.onMap,
    required this.onPrefs,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mapped = mappedAccountName != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.sms_rounded, size: 16, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  mapped
                      ? '→ $mappedAccountName'
                      : '${count} msg${count == 1 ? '' : 's'} · unmapped',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: mapped
                        ? kSuccessColor
                        : cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onMap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: cs.primary,
            ),
            child: Text(mapped ? 'Remap' : 'Map'),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 18),
            tooltip: 'Parsing preferences',
            onPressed: onPrefs,
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  final SmsRule rule;
  final String accountName;
  final String categoryName;
  final VoidCallback onDelete;
  const _RuleRow({
    required this.rule,
    required this.accountName,
    required this.categoryName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: isDark ? 0.45 : 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.senderId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  '${rule.transactionType} → $accountName · $categoryName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: kDangerColor),
            tooltip: 'Delete rule',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _SenderPrefRow extends StatelessWidget {
  final SmsSenderPref pref;
  final VoidCallback onTap;
  const _SenderPrefRow({required this.pref, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final suppressed = pref.suppressedKinds
        .map((k) => k == 'otp' ? 'OTP' : k[0].toUpperCase() + k.substring(1))
        .toList();
    final subtitle = !pref.parseAllowed
        ? 'Parsing off'
        : suppressed.isEmpty
            ? 'All messages shown'
            : 'Hiding: ${suppressed.join(', ')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: isDark ? 0.45 : 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Icon(
            pref.parseAllowed ? Icons.tune_rounded : Icons.block_rounded,
            size: 18,
            color: pref.parseAllowed ? cs.primary : kDangerColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pref.senderId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            tooltip: 'Manage',
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

// ── Per-sender preferences sheet ─────────────────────────────────────────────
class _SenderPrefSheet extends StatefulWidget {
  final String sender;
  const _SenderPrefSheet({required this.sender});

  @override
  State<_SenderPrefSheet> createState() => _SenderPrefSheetState();
}

class _SenderPrefSheetState extends State<_SenderPrefSheet> {
  static const _kinds = [
    ('otp', 'OTP / codes'),
    ('promotional', 'Promotional'),
    ('personal', 'Personal'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vm = context.watch<SmsInboxViewModel>();
    final pref = vm.smsSenderPref(widget.sender);
    final parseAllowed = vm.isSmsSenderParseAllowed(widget.sender);

    return SheetShell(
      title: 'Parsing preferences',
      subtitle: widget.sender,
      showHandle: true,
      children: [
        // ── Parse allow/deny ──────────────────────────────────────────────
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: parseAllowed,
          onChanged: (v) async {
            await vm.setSmsSenderParseAllowed(widget.sender, v);
          },
          title: const Text('Parse messages from this sender',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text(
            'When off, all messages from this sender are ignored.',
            style: TextStyle(fontSize: 11.5),
          ),
        ),
        const Divider(height: 24),

        // ── Per-kind suppression ──────────────────────────────────────────
        Text("DON'T SHOW AGAIN",
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(
          'Hide specific kinds of messages. Transactions are never hidden.',
          style: TextStyle(
              fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 8),
        ..._kinds.map((k) {
          final kind = k.$1;
          final label = k.$2;
          final suppressed = vm.isSmsKindSuppressed(widget.sender, kind);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: suppressed,
            onChanged: (v) async {
              if (v ?? false) {
                await vm.suppressSmsKind(widget.sender, kind);
              } else {
                await vm.unsuppressSmsKind(widget.sender, kind);
              }
            },
            title: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        }),
        const SizedBox(height: 8),

        // ── Reset ─────────────────────────────────────────────────────────
        if (pref != null)
          TextButton.icon(
            onPressed: () async {
              await vm.resetSmsSenderPrefs(widget.sender);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset preferences'),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: kDangerColor,
            ),
          ),
      ],
    );
  }
}

// ── Sender → account mapping sheet ───────────────────────────────────────────
class _SenderMapSheet extends StatefulWidget {
  final String sender;
  const _SenderMapSheet({required this.sender});

  @override
  State<_SenderMapSheet> createState() => _SenderMapSheetState();
}

class _SenderMapSheetState extends State<_SenderMapSheet> {
  late String _type;
  late String? _accountId;
  late String? _categoryId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    _type = 'expense';
    final accounts = app.accounts.where((a) => !a.isCredit).toList();
    _accountId = accounts.isNotEmpty ? accounts.first.id : null;
    final cats = app.userCategories.where((c) => c.type == _type).toList();
    _categoryId = cats.isNotEmpty ? cats.first.id : null;
  }

  void _onTypeChanged(String t) {
    setState(() {
      _type = t;
      if (t != 'transfer') {
        final cats = context
            .read<AppProvider>()
            .userCategories
            .where((c) => c.type == t)
            .toList();
        if (_categoryId == null ||
            (context.read<AppProvider>().categoryById(_categoryId!)?.type !=
                t)) {
          _categoryId = cats.isNotEmpty ? cats.first.id : null;
        }
      }
    });
  }

  Future<void> _save() async {
    if (_accountId == null) {
      showAppSnackbar(context, 'Select an account');
      return;
    }
    if (_type != 'transfer' && _categoryId == null) {
      showAppSnackbar(context, 'Select a category');
      return;
    }
    setState(() => _busy = true);
    await context.read<SmsInboxViewModel>().saveSmsRule(
          senderId: widget.sender,
          accountId: _accountId!,
          categoryId: _type == 'transfer' ? 'sys_transfer' : _categoryId!,
          transactionType: _type,
        );
    if (!mounted) return;
    Navigator.pop(context);
    showAppSnackbar(context, 'Mapped $widget.sender');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    context.watch<CategoriesViewModel>();
    final cs = Theme.of(context).colorScheme;
    final cats = app.userCategories.where((c) => c.type == _type).toList();
    final accounts = app.accounts.where((a) => !a.isCredit).toList();

    return SheetShell(
      title: 'Map sender',
      subtitle: widget.sender,
      showHandle: true,
      children: [
        // ── Type ──────────────────────────────────────────────────────────
        TypeToggleChips(
          selectedValue: _type,
          firstValue: 'expense',
          firstLabel: 'Expense',
          firstColor: kDangerColor,
          secondValue: 'income',
          secondLabel: 'Income',
          secondColor: kSuccessColor,
          thirdValue: 'transfer',
          thirdLabel: 'Transfer',
          thirdColor: kCertificateColor,
          onChanged: _onTypeChanged,
        ),
        const SizedBox(height: 16),

        // ── Account ───────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Text('ACCOUNT',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(letterSpacing: 1)),
            ),
            TextButton.icon(
              onPressed: () => AccountsScreen.openSheet(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New account'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hairlineBorderColor(cs)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No accounts yet. Create one to map this sender to.',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
              ],
            ),
          )
        else
          AccountCardPicker(
            accounts: accounts,
            selectedId: _accountId,
            onSelected: (id) => setState(() => _accountId = id),
          ),
        const SizedBox(height: 14),

        // ── Category (not for transfers) ──────────────────────────────────
        if (_type != 'transfer') ...[
          Text('CATEGORY',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(letterSpacing: 1)),
          const SizedBox(height: 8),
          CategoryChipPicker(
            categories: cats,
            selectedId: _categoryId,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 14),
        ],

        // ── Action ────────────────────────────────────────────────────────
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded),
          label: const Text('Save mapping'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}
