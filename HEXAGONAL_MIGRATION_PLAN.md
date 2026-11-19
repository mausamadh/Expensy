# Expensy — Hexagonal + DDD Migration Plan

Status: **proposed** · Scope: `lib/` only (no schema rewrite, no feature changes) · Strategy: **strangler pattern** — every phase ships green.

---

## 1. Goals & non-goals

**Goals**
- Domain logic (money math, invariants, rules) lives in pure Dart with **zero Flutter/Drift imports** and is unit-testable without a device.
- All I/O (DB, SMS, files, network, notifications, time) sits behind **ports** (interfaces) implemented by **adapters**.
- One **use case** per user intent; `AppProvider` shrinks from a 4,984-line god object to a thin composition shell + per-feature view models.
- Dependency injection replaces the 9+ singletons.
- CI guard mechanically enforces the layering so it cannot rot.

**Non-goals**
- No Drift schema change, no data migration, no UI redesign.
- No big-bang rewrite; no phase may leave the app non-shippable.
- No new framework beyond `get_it` (single dependency addition).

## 2. Current-state facts (baseline)

| Fact | Value |
|---|---|
| `lib/providers/app_provider.dart` | 4,984 lines, **142 public methods**, ChangeNotifier |
| `lib/models/models.dart` | 25 anemic classes (Account, AppTransaction, Budget, RecurringPayment, Loan, Certificate, SmsInboxItem, …) |
| `lib/services/` | 22 files, **9+ singletons** (`NotificationService._()`, `QuickAddService.instance`, reminder services, …) |
| DB | Drift `AppDatabase.instance` singleton + static `DBHelper` facade |
| DI | none |
| Time | `DateTime.now()` scattered; no `Clock` |
| Screens importing `app_provider.dart` | 39 |
| Tests | 41 files, incl. golden backup roundtrip, balance integrity, 75 SMS tests |
| Guardrails | `tool/ci_guard.dart --enforce` (DB-in-UI == 0), `flutter analyze` |

## 3. Target architecture

```
lib/
├── domain/                      # PURE DART. No flutter/, drift, plugins.
│   ├── shared/                  #   Value objects & primitives shared by contexts
│   │   ├── money.dart           #   Money (int minor units + ISO code) — already the storage shape
│   │   ├── date_range.dart
│   │   └── ids.dart             #   AccountId, TransactionId, … (typed wrappers)
│   ├── ledger/                  # Bounded context: accounts, transactions, transfers, splits
│   │   ├── entities/            #   Account, Transaction, TransferLeg, Split (rich, with invariants)
│   │   ├── services/            #   BalanceApplier (atomic delta), TransferValidator
│   │   └── ports/               #   TransactionRepository, AccountRepository, …
│   ├── budgeting/               # Budgets, pacing, rollup (moves providers/aggregations.dart here)
│   ├── recurring/               # RecurringPayment, sweep rules
│   ├── sms_import/              # SmsMessage, ParsedTransaction, sender prefs, rules
│   ├── backup/                  # BackupManifest, validation rules, safety-snapshot policy
│   ├── lending/                 # LendedPerson/LendedMoney, loans, credit cards, certificates
│   └── settings/                # AppSettings as a domain value object
├── application/                 # Use cases (driving ports). Pure Dart, depend on domain only.
│   ├── ledger/                  #   AddTransaction, AddTransfer, DeleteTransactionWithUndo, …
│   ├── sms_import/              #   ScanSmsInbox, ImportSmsCandidate, DeclineSmsMessage, SaveSmsRule
│   ├── backup/                  #   CreateBackup, RestoreBackup (validator + safety snapshot), …
│   └── …
├── adapters/                    # Infrastructure (driven-port implementations)
│   ├── drift/                   #   DriftTransactionRepository, … (wraps existing AppDatabase)
│   ├── sms/                     #   ExpensySmsSource (plugin), SmsInboxRepository
│   ├── storage/                 #   SafFileStorage, BackupFileStorage
│   ├── network/                 #   HttpExchangeRateProvider
│   ├── notifications/           #   FcmNotificationGateway (replaces singleton)
│   ├── preferences/             #   SharedPrefsSettingsStore
│   └── time/                    #   SystemClock (+ FakeClock for tests)
├── composition/
│   └── root.dart                # get_it registration; the ONLY place adapters are constructed
├── presentation/                # Today's screens/ + widgets/ + theme/ + l10n/
│   └── viewmodels/              # Per-feature ChangeNotifiers (SmsInboxViewModel, LedgerViewModel, …)
└── main.dart                    # Bootstrap: build composition root, register, runApp
```

**Dependency rule (enforced by CI guard):**
`presentation → application → domain ← adapters`. Only `composition/root.dart` may import `adapters/`. `domain/` imports nothing from the app.

## 3a. AGENTS.md rule mapping (binding constraints)

Every AGENTS.md rule must survive the migration — mapped to its new home:

| # | AGENTS.md rule | New home in hexagonal structure |
|---|---|---|
| 1 | UI never imports DB layer; all mutations via provider | Strengthened: `presentation/` may not import `adapters/` or `database/` (guard-enforced); mutations go through use cases |
| 2 | Zone-based mutex around DB/balance mutations | Mutex moves to the **application layer** (a `UnitOfWork`/`MutationGate` service registered in the composition root); use cases run inside it. Never a re-entrant counter lock |
| 3 | Atomic balance updates via SQL deltas | `BalanceApplier` domain service; the Drift adapter keeps `applyBalanceDelta` — no read-modify-write, ever |
| 4 | Aggregations exclude `isTransfer` + `isInvestment` | `FinancialAggregations` moves to `domain/budgeting/` with the exclusions encoded as domain invariants + dedicated tests |
| 5 | Backup safety net (validator + pre-restore snapshot + golden roundtrip) | `RestoreBackup` use case enforces validator + `expensy_prerestore_<ts>.json` snapshot; golden roundtrip test runs in every phase |
| 6 | Provider collections reassigned with fresh list instances | Same rule applies to **view models**: `transactions = next`, never in-place mutation (UI memoization caches rely on reference inequality) |
| 7 | Theme constants + shared widgets for popups | Unchanged — `presentation/` keeps `theme/` + `widgets/shared_widgets.dart` as-is |
| 8 | Subcategories single-level `parent_id`; transfers always `sys_transfer`, distinct accounts, preserved `transferGroupId` | `TransferValidator` domain service encodes all three invariants; `userCategories` (hidden system categories excluded) becomes a domain query |

## 4. Bounded contexts, ports, and use cases

### 4.1 Ledger (highest value, highest risk)
- **Entities:** `Account`, `Transaction`, `TransferLeg` (pair, `transferGroupId`), `Split`, `Category`
- **Invariants to encode:** atomic balance delta (no read-modify-write), transfer legs always `sys_transfer` + distinct accounts + preserved group id, cross-currency needs rates (`RatesUnavailableException` moves here)
- **Ports:** `AccountRepository`, `TransactionRepository`, `CategoryRepository`, `Clock`, `ExchangeRateProvider`
- **Use cases (from the 142 provider methods):** `AddTransaction`, `UpdateTransaction`, `DeleteTransaction(WithUndo)`, `AddTransfer`, `SaveTransactionSplits`, `AddAccount`, `UpdateAccount`, `DeleteAccountWithUndo`, `ReorderAccounts`, `ConvertToMain`, `FindPossibleDuplicates`, `ExportTransactionsExcel`

### 4.2 SmsImport (pilot — already 80% isolated)
- **Entities:** `SmsMessage`, `ParsedTransaction` (already pure in `services/sms_parser/`), `SmsInboxItem`, `SmsSenderPref`, `SmsRule`
- **Ports:** `SmsSource` (plugin), `SmsInboxRepository`, `SmsRuleRepository`, `Clock`
- **Use cases:** `ScanSmsInbox`, `ParseSmsMessage` (live capture), `ImportSmsCandidate` (incl. sender→account memory), `DeclineSmsMessage` (per-message), `RestoreSmsCandidate`, `SaveSmsRule`, `SetSmsSenderPref`
- **Note:** `sms_parser/` moves to `domain/sms_import/` nearly untouched; `sms_import_service.dart` splits into `SmsSource` adapter + use cases.

### 4.3 Budgeting
- **Moves:** `providers/aggregations.dart` → `domain/budgeting/` (pure math, already close)
- **Use cases:** `AddBudget`, `UpdateBudget`, `DeleteBudgetWithUndo`, `BudgetRollover`, `CheckBudgetAlert`
- **Ports:** `BudgetRepository`, `TransactionRepository` (read), `NotificationGateway`

### 4.4 Recurring
- **Use cases:** `AddRecurring`, `SkipNextRecurring`, `ProcessRecurringSweep` (from `recurring_payment_processor.dart`), `CheckAndProcessAutoPay`
- **Ports:** `RecurringRepository`, `TransactionRepository`, `Clock`, `TimerScheduler`

### 4.5 Lending (loans, lended, credit cards, certificates)
- **Use cases:** `AddLoan`, `RecordLoanPayment`, `SkipLoanInstallment`, `SettleCreditCard`, `CheckAndProcessCertificates`, `AddLended`, `SettleLended`
- **Ports:** `LoanRepository`, `LendedRepository`, `CertificateRepository`, `NotificationGateway`, `Clock`

### 4.6 Backup
- **Moves:** `backup_builder.dart`, `backup_validator.dart`, `backup_encryption_service.dart`, `auto_backup_service.dart` → use cases + `FileStorage`/`Keychain` ports
- **Use cases:** `CreateBackup`, `CreateSelectiveBackup`, `RestoreBackup` (validator + pre-restore safety snapshot — keep the existing safety-net rules), `UndoLastRestore`, `RunAutoBackup`
- **Ports:** `BackupFileStorage` (SAF/files), `Keychain`, `Clock`

### 4.7 Settings & FX
- `AppSettings` → domain value object; `SharedPrefsSettingsStore` port
- `ExchangeRateProvider` port; `HttpExchangeRateProvider` adapter (existing `http` dep)

### 4.8 Cross-cutting
- **`Clock` port** — every `DateTime.now()` in domain/application goes through it; `FakeClock` in tests
- **`NotificationGateway` port** — kills the 6 reminder-service singletons (they become use cases taking the gateway)
- **`QuickAddService`** → `QuickAdd` use case

## 5. Phases

Each phase: **implement → tests green → CI guard green → analyze clean → commit**. No phase touches two contexts at once.

### Phase 0 — Foundations (1–2 days)
- [ ] Add `get_it` to `pubspec.yaml`
- [ ] Create `lib/domain/shared/` (`Money`, `DateRange`, ids) + unit tests
- [ ] Create `lib/adapters/time/clock.dart` (`Clock` port, `SystemClock`, `FakeClock`)
- [ ] Create `lib/composition/root.dart` skeleton (empty `GetIt` registration)
- [ ] Define `MutationGate` (zone-based mutex, per AGENTS.md rule 2) in `application/` — the future home of the provider's `_mutex`
- [ ] Extend `tool/ci_guard.dart`:
  - `domain/` must not import `package:flutter/`, `drift`, or any plugin
  - `application/` must not import `adapters/` or `presentation/`
  - `presentation/` must not import `adapters/`
  - keep existing `DB in UI == 0`
- [ ] **Acceptance:** guard passes on the untouched tree; `Money` tests pass; zero behavior change.

### Phase 1 — SMS Import pilot (2–4 days)
- [ ] Move `services/sms_parser/` → `domain/sms_import/` (pure, near-verbatim)
- [ ] Define ports: `SmsSource`, `SmsInboxRepository`, `SmsRuleRepository`
- [ ] Adapters: `ExpensySmsSource`, Drift inbox/rule repositories
- [ ] Use cases: `ScanSmsInbox`, `ParseSmsMessage`, `ImportSmsCandidate`, `DeclineSmsMessage`, `RestoreSmsCandidate`, `SaveSmsRule`, `SetSmsSenderPref`
- [ ] `SmsInboxViewModel` (ChangeNotifier) replaces the SMS slice of `AppProvider`; `sms_inbox_screen.dart` consumes the view model
- [ ] Register in composition root; delete SMS methods from `AppProvider`
- [ ] **Acceptance:** all 75+ SMS tests pass (rewired to fakes where they hit I/O); golden roundtrip unaffected; guard green.

### Phase 2 — Ledger (the big one, 1–2 weeks, split into 2a/2b)
- **2a — read side:** `AccountRepository`/`TransactionRepository`/`CategoryRepository` ports + Drift adapters wrapping the existing `AppDatabase` (no SQL changes); `aggregations.dart` → `domain/budgeting/`; provider getters delegate to repositories.
- **2b — write side:** `AddTransaction`, `AddTransfer`, `DeleteTransactionWithUndo`, `SaveTransactionSplits`, account CRUD use cases; atomic balance delta becomes a domain service called through the repository port; `RatesUnavailableException` → domain.
- [ ] **Acceptance:** `balance_integrity_test.dart`, `splits_test.dart`, `relogic_and_user_restore_test.dart` green; undo/redo behavior byte-identical.

### Phase 3 — Budgeting + Insights (2–3 days)
- [ ] Budget use cases; pacing/rollup in domain; `InsightsScreen`/`WrappedScreen` read via `TransactionRepository`
- [ ] **Acceptance:** `budget_pacing_test.dart`, `rollover_budget_test.dart`, `wrapped_test.dart` green.

### Phase 4 — Recurring + Reminders + FX (2–3 days)
- [ ] Recurring use cases + `TimerScheduler` port; 6 reminder singletons → use cases + `NotificationGateway`; `HttpExchangeRateProvider`
- [ ] **Acceptance:** `recurring_*` tests, `autopay_catchup_test.dart` green.

### Phase 5 — Backup (2–3 days)
- [ ] `FileStorage`/`Keychain` ports; `CreateBackup`/`RestoreBackup`/`UndoLastRestore` use cases preserving validator + safety-snapshot rules
- [ ] **Acceptance:** `golden_backup_roundtrip_test.dart`, `backup_encryption_test.dart`, `selective_backup_test.dart`, `auto_backup_test.dart` green.

### Phase 6 — Slim the provider (2–3 days)
- [ ] Remaining provider methods → per-feature view models (Ledger, Accounts, Home, …) — view models follow the same fresh-list-instance reactivity rule as `AppProvider` (AGENTS.md rule 6)
- [ ] Delete `DBHelper` static facade (callers go through repositories)
- [ ] `AppProvider` ≤ ~500 lines: settings + navigation state + composition wiring only
- [ ] **Acceptance:** full `flutter test` green; guard green; `AppProvider` line count target met.

## 6. Test strategy per phase

| Layer | Strategy |
|---|---|
| Domain | Pure unit tests, no Flutter binding (fast, deterministic via `FakeClock`) |
| Application | Use-case tests with in-memory fake ports (pattern already proven by `NativeDatabase.memory()` tests) |
| Adapters | Existing integration-style tests (Drift in-memory, plugin channel mocks) |
| Presentation | Existing widget tests, now against view models + fakes |
| Safety net | `golden_backup_roundtrip_test.dart` + `balance_integrity_test.dart` run in **every** phase |

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Ledger rewrite breaks financial invariants | 2a/2b split; adapters wrap existing `AppDatabase` (no SQL change); balance-integrity + golden tests every commit |
| 39 screens coupled to `AppProvider` | Keep `AppProvider` as a facade during phases 2–5 (delegates to use cases); only Phase 6 removes it |
| Singleton services used by workmanager/background | `NotificationGateway` + composition root accessible from background entrypoints (same `GetIt` instance) |
| Scope creep / half-migrated state | One context per phase; CI guard rules added in Phase 0 make regressions loud |
| Solo-maintainer review burden | Small PRs per phase; each phase independently revertable |

## 8. Definition of done (whole migration)

- `domain/` + `application/` import no Flutter/Drift/plugin code (guard-enforced)
- `AppProvider` ≤ ~500 lines; no static singletons in `lib/`
- All 41 test files green; guard green; `flutter analyze` clean
- `main.dart` is the only place that knows concrete adapter types
