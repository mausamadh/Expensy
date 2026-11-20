# Expensy Autonomous SMS Parser Plan

Status: proposed

## Implementation Progress

- Phase A — persisted event/outbox foundation: implemented.
- Phase B — verification data model and threshold learning: domain/repository/use-case foundation implemented.
- Phase C — app-start live capture and startup reconciliation: startup scan/live preference foundation implemented.
- Active learning proposals now override matching inbox parse fields after confirmation.
- Conservative/balanced/high-confidence import policy: domain decision foundation implemented.
- SMS outcome notification gateway: implemented.
- Manifest-declared Android SMS receiver and startup reconciliation: implemented.
- Direct Drift ledger gateway: SMS writes no longer use `AppProvider` mutation methods.
- SMS event/outbox, verification, policy, live preference, notification, and backup table foundations: implemented.
- Connected-device smoke validation: passed on Samsung SM-E225F (device RZ8T3207LAR).
  - latest debug APK installed successfully;
  - app launched and remained running;
  - `SmsBackgroundReceiver` is merged and registered for `SMS_RECEIVED`;
  - READ_SMS, RECEIVE_SMS, and POST_NOTIFICATIONS are granted in the primary user.
- Old and current SMS reconciliation:
  - startup and manual inbox scans use a 5,000-SMS reconciliation limit;
  - newly discovered high-confidence, fully-routed transaction candidates are auto-imported;
  - ambiguous candidates remain pending and trigger verification notifications;
  - import failures trigger actionable import-failed notifications.
- Old-SMS implementation validation:
  - focused old-SMS scan tests pass;
  - safe candidate auto-import test passes;
  - ambiguous candidate verification-notification test passes;
  - latest APK build passed; final reinstall is pending USB reconnection.
- First-run clean-entry and account reconciliation:
  - ask for SMS auto-import consent before historical SMS is auto-imported;
  - show live "Loading SMS transactions: N messages" UI while reconciliation runs;
  - suggest bank, debit-card, credit-card, wallet, and CIT retirement accounts after parsing;
  - open account/card sheets so the user enters the current balance and linked funding account;
  - keep CIT retirement contributions low-confidence and require verification;
  - detect fund-transfer/card-payment patterns as transfers or transfer candidates, never unverified expense/income guesses;
  - auto-close SMS outcome notifications after five seconds.
- Transfer and retirement-account handling:
  - CIT/National investment/retirement SMS are suggested as savings/investment accounts and kept under verification;
  - outgoing fund transfers and credit-card payments are marked as transfer candidates;
  - incoming fund transfers remain income candidates rather than guessed transfers;
  - auto-imported transfers still require distinct source/destination accounts and `sys_transfer`.
- Device fixture learning:
  - exported 7,479 device inbox rows and 3,954 app inbox candidates privately;
  - app state currently contains 1,445 imported, 138 dismissed, and 2,371 pending candidates;
  - added redacted Nepalese fixtures for NT Rupee deductions/credits, Siddhartha withdrawals/deposits, and credit-card due blocking;
  - parser fixtures for these device-derived cases pass.
- Launch-time optimization:
  - 5,000-SMS startup reconciliation runs only after the first Flutter frame;
  - live capture startup is deferred until the app frame is visible;
  - SMS inbox/rule/preference database loading is deferred until after the first frame;
  - startup no longer awaits the SMS scan before calling `runApp`.
  - latest startup-optimized APK build passed; cold-start timing is pending stable USB reconnection.
- Startup parsing reliability:
  - provider/account data now loads before SMS reconciliation, preventing auto-import from racing with an empty ledger context;
  - permission grants immediately trigger historical reconciliation;
  - startup permission, scan completion, and scan failure are visible in the app instead of being silently skipped;
  - existing installs are told when messages are parsed but auto-import consent is still off.
  - loading UI now reports the actual SMS rows returned by the device query, not the configured scan limit.
- Remaining implementation phases: broader country fixture expansion and full live SMS/notification behavior testing with real incoming messages.
- Remaining implementation phases: true Android background receiver/WorkManager, notification deep-link routing, ledger bridge removal, parser breadth, event crash tests, parser fixture expansion, device testing, and migration hardening.

## Objective

Build a fully autonomous, Android/IOS SMS transaction parser that:

- receives and reconciles SMS messages automatically;
- parses banks, cards, credit cards, wallets, transfers, deposits, refunds, fees, and related transaction formats;
- imports high-confidence transactions without user intervention;
- asks for verification only when the result is uncertain or incomplete;
- learns confirmed corrections and improves later parsing;
- remains safe for financial data and preserves existing ledger, transfer, backup, and concurrency rules.

The implementation uses DDD bounded contexts, hexagonal ports/adapters, and persisted event-driven processing.

## Existing Foundation

The SMS context already has:

- pure Dart parsing entities and pipeline in `lib/domain/sms_import/`;
- template registry and fallback matcher;
- SMS source, inbox, rule, preference, settings, and ledger ports;
- Drift and plugin adapters;
- a live-capture controller;
- sender preferences, hash deduplication, inbox rules, and OTP suppression;
- Android SMS read/receive permissions and live event channels;
- a presentation `SmsInboxViewModel`;
- targeted parser and SMS tests.

The current implementation is not yet autonomous:

- live capture starts only from the SMS screen;
- no verification-learning aggregate or parser template-learning workflow exists;
- SMS reception is not a background process;
- no persisted event/outbox or crash-recovery pipeline exists;
- there is no parsed/imported SMS notification and deep-link workflow;
- the SMS ledger gateway still bridges to `AppProvider`;
- the built-in registry currently includes a Kenya-only template pack;
- app restarts, missed SMS, multipart SMS, and duplicate event delivery need explicit handling.

## Target Architecture

```text
Android SMS receiver / SMS inbox
        |
        v
SMS ingestion adapter
        |
        v
SmsReceived event -> persisted outbox
        |
        v
SMS application workflow
  - normalize SMS
  - deduplicate
  - classify
  - match template
  - run fallback parser
  - score confidence
  - persist candidate
  - request verification or import
        |
        +--> Verification application workflow
        |    - apply corrections
        |    - learn template/rule
        |    - publish SmsVerificationApplied
        |
        v
Ledger Gateway / Ledger use case
        |
        v
SmsImported / SmsImportFailed event
        |
        v
Notification adapter and UI deep link
```

### Domain model

The SMS bounded context should own:

- `SmsMessage`
- `SmsTransactionCandidate`
- `ParsedTransaction`
- `ParseConfidence`
- `SmsTemplateRevision`
- `SenderIdentity`
- `SmsVerification`
- `SmsRoutingRule`
- `SmsLearningProposal`
- `SmsProcessingState`
- `SmsIdempotencyKey`

An unknown or ambiguous message remains a first-class candidate. It must never be silently discarded or silently represented as an expense.

### Domain events

Add explicit, persisted events:

- `SmsReceived`
- `SmsParseRequested`
- `SmsParseCompleted`
- `SmsVerificationRequested`
- `SmsVerificationSubmitted`
- `SmsVerificationApplied`
- `SmsTemplateLearned`
- `SmsImportRequested`
- `SmsImported`
- `SmsImportFailed`
- `SmsNotificationRequested`

Events and their processing state must survive process and app restarts.

### Ports

Add or replace SMS ports for:

- persistent event/outbox storage;
- background SMS ingestion;
- inbox reconciliation;
- template repository and template revisions;
- verification repository;
- ledger import;
- notification delivery;
- retry scheduling;
- clock/time;

Adapters may depend on Flutter, Android, Drift, plugins, or WorkManager. Domain and application code must not.

### Learning safety

A user correction should first create a learning proposal, not an unconditional parser rule.

Learning must include:

- confirmed amount, currency, direction, merchant, account, category, date, reference, and transfer destination;
- original sender and normalized message;
- matched template and parser revision;
- confirmation count;
- threshold/revision activation state;
- explicit user opt-in for remembering a pattern.

No learned rule may bypass:

- `sys_transfer` for transfers;
- distinct source and destination accounts;
- preserved `transferGroupId`;
- system/investment category exclusions;
- atomic ledger balance updates.

## Implementation Phases

### Phase A: Event infrastructure and persistence

Create a persisted outbox and idempotency model for SMS processing.

Tasks:

- define domain event types and event envelope metadata;
- add event/outbox tables or repository methods;
- add event dispatcher retry and failure states;
- use stable raw hash plus message identity for deduplication;
- add crash-safe state transitions;
- add application tests for replay and duplicate delivery.

Acceptance:

- a received SMS is persisted before parsing;
- each event is delivered once or recorded as safely replayable;
- scan, live capture, and background ingestion converge on the same dedup key;
- replay cannot create duplicate ledger transactions.

### Phase B: Verification and learning

Replace routing-only rule upserts with a real correction and learning workflow.

Tasks:

- add verification fields and candidate correction entity;
- capture amount, currency, direction, merchant, date, account, category, and transfer destination;
- persist `SmsVerificationSubmitted` and `SmsVerificationApplied`;
- distinguish one-off correction from a reusable learning proposal;
- support sender, merchant, account, currency, and direction confidence;
- require explicit learning or a confirmation threshold before activation;
- version learned patterns and templates;
- reject conflicting or unsafe transfer corrections.

Acceptance:

- verification makes a next similar message parse more reliably;
- corrections are replayable and auditable;
- unconfirmed unknown patterns do not change global behavior;
- transfer verification always remains structurally valid.

### Phase C: Persistent Android capture

Move live SMS processing into app-owned background infrastructure.

Tasks:

- add a manifest-declared, exported-safe Android SMS receiver or supported foreground path;
- initialize capture through app composition/startup and not only the SMS screen;
- add permission and default-SMS-app state handling;
- process concatenated multipart SMS before parsing;
- reconcile missed messages against the inbox on startup;
- add WorkManager retry for queued processing;
- add foreground/live capture controls with a persisted enabled preference;
- stop or suspend cleanly on denied permissions and startup failures.

Acceptance:

- an enabled app processes messages while running in background;
- restart scans reconcile missed messages;
- multipart SMS produces one candidate;
- denied receive/read permissions produce no crash or silent failure;
- live and startup scans do not duplicate work.

### Phase D: Notifications and deep links

Add user-facing notifications for parsing outcomes.

Tasks:

- notify on successful import;
- notify when verification is required;
- notify on parse/import failure;
- include duplicate/suppressed behavior settings;
- deep-link notifications to the exact candidate or ledger transaction;
- reuse the existing notification permission and Android channels;
- move notification delivery behind a gateway port.

Acceptance:

- every ambiguous or failed candidate has an actionable notification;
- successful imports are observable;
- notifications open the correct inbox item or transaction;
- notification settings can suppress optional noise.

### Phase E: Parser breadth

Expand the parser from the existing Kenya pack to generalized transaction parsing.

Tasks:

- improve generic amount, currency, direction, merchant, date, reference, balance, and account-tail extraction;
- add card and wallet signals;
- add purchases, refunds, reversals, ATM, fee, interest, rewards, EMI, cheque, deposit, pending, and card-present formats;
- add same-bank and inter-bank transfer detection;
- add multi-currency and exchange detection;
- separate income, expense, transfer, internal transfer, investment, and no-transaction messages;
- add token and semantic evidence scoring;
- add country packs and fixture registries for Kenya, Nepal, India, and then other supported locales;
- retain template revision precedence and deactivation behavior.

Acceptance:

- fixtures cover each supported country and major transaction type;
- parser output includes amount, currency, direction, merchant/reference, date, and confidence;
- promotional, OTP, loan-offer, balance-only, and personal messages are not booked;
- unknown and low-confidence messages remain in the verification queue.

### Phase F: Autonomous import policy

Define safe automatic and verification-required thresholds.

Tasks:

- add policy domain service;
- classify high confidence, review, and reject states;
- require review for missing account, currency, merchant ambiguity, card ambiguity, or transfer ambiguity;
- auto-import only transactions with enough evidence and a valid target account/category;
- require a configured credit-card account for card transactions where applicable;
- publish verification or import events after policy decision;
- add policy settings for conservative/balanced/automated modes.

Acceptance:

- high-confidence transactions import automatically;
- ambiguity never produces a guessed account/category or transfer;
- policy behavior is deterministic and unit-tested;
- policy changes are auditable.

### Phase G: Ledger decoupling

Remove the SMS context's temporary dependency on `AppProvider`.

Tasks:

- implement SMS use-case calls through ledger repository/write ports;
- add atomic balance and transfer operations to the ledger context;
- preserve transfer pair and transfer-group invariants;
- migrate aggregation and category lookups off provider-backed SMS context adapters;
- remove `AppProviderLedgerGateway` and `AppProviderLedgerContext`;
- keep UI mutations behind application use cases.

Acceptance:

- SMS has no import dependency on `AppProvider`;
- SMS imports use atomic ledger operations;
- transfer, balance-integrity, and golden roundtrip tests pass.

### Phase H: Migration completion and hardening

Finish related migration work and harden the feature.

Tasks:

- continue the provider extraction plan in `HEXAGONAL_MIGRATION_PLAN.md`;
- replace notification singleton usage for SMS outcomes;
- reduce direct infrastructure access in presentation;
- run full test suites and device-level smoke tests;
- add crash, permission, and recovery diagnostics;
- document supported countries and parser limitations.

Acceptance:

- `AppProvider` reaches the migration target;
- CI guard remains green;
- full Flutter tests pass;
- backup and balance integrity tests pass;
- architecture documentation matches the final implementation.

## Test Plan

Add or expand tests for:

- SMS receive, startup reconcile, and missed-SMS catch-up;
- multipart SMS assembly;
- deduplication across scan, receiver, retry, and outbox replay;
- event crash recovery and retry;
- verification submission and replay;
- learning threshold and template activation;
- Kenya and Nepal fixtures;
- debit card, credit card, prepaid card, and wallet formats;
- refund, reversal, fee, EMI, cheque, ATM, deposit, pending, and transfer formats;
- no-transaction filtering for OTP, promotional, personal, and balance-only messages;
- transfer source/destination distinction and transfer group creation;
- account/category ambiguity;
- notification permission and deep-link routing;
- Android receive/read permission states;
- background process restart;
- golden backup roundtrip and balance integrity.

## Security and Privacy

- never log raw SMS bodies or sensitive transaction details;
- store the minimum required parsed fields;
- encrypt or follow the app's existing backup policy for any retained raw SMS;
- expose no SMS data outside explicit app-owned ports;
- make opt-out, delete, and sender blocking work without retaining hidden candidates;
- require Android permission prompts and show clear privacy rationale;
- preserve existing export and backup safety behavior.

## Sequence and Milestones

1. Persisted outbox, idempotency, and domain events.
2. Verification data model and correction learning.
3. Android background capture and reconciliation.
4. Notifications and deep-link UX.
5. Ledger bridge removal.
6. Generic parser expansion and country fixture packs.
7. Autonomous import policy.
8. Migration completion and full hardening.

The event, verification, and background capture milestones should ship before template breadth so the system can safely learn and handle unknown formats.

## Definition of Done

- SMS is processed without requiring manual inbox scan.
- High-confidence transactions import automatically.
- Ambiguous transactions generate review notifications.
- Verification corrections improve future parsing.
- Unknown messages are retained safely instead of silently discarded.
- Event/outbox processing survives restarts and retries.
- Duplicate SMS cannot create duplicate ledger transactions.
- Card and bank transactions cover all major direction and transfer cases.
- Transfer and account/category invariants remain enforced.
- Notification and inbox deep links work.
- The SMS context has no provider/database leakage.
- CI guard, Flutter tests, backup roundtrip, and balance integrity checks pass.
