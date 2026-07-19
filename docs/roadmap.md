# Delivery roadmap

The build order is a dependency graph, not a list of equally parallel features.
Schema and backup protect the asset; configuration enables capture; real capture
data informs later ergonomics. Work may be parallelized only when it does not
cross a decision or evidence gate.

RXcalc is an independent stateless delivery track: it may advance without a
SwiftData decision because it cannot read or write the ledger store, but every
clinical formula still requires its own source, version, tests, and approval.

## Current status

| Milestone | Status | Exit evidence |
|---|---|---|
| F0 — repository and doctrine | Complete | Clean public repository, README boundaries, zero dependencies |
| F1 — versioned persistence | Verified | Xcode 16.4 Release build, analyzer, in-memory tests, and file-backed close/reopen test pass on iOS 18.5 CI |
| F2 — backup foundation | Verified | Populated all-model store restores and logically re-exports identically in hosted tests |
| F3 — privacy build controls | Verified | Clean Xcode build passes and CI proves a planted `URLSession` reference fails the build phase |
| F4 — policy-neutral configuration and backup evolution | Verified | Implementation commit `ade0c7f` passed the Xcode 16.4/iOS 18.5 Release build, analyzer, simulator tests, and boundary probe in [hosted run 29439588632](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29439588632) |
| F5 — boundary-control hardening | Verified | Implementation series through [`dda1ab8`](https://github.com/Ayyitskevin/Hippocrates/commit/dda1ab8c64c0b7979bd715a74511868be5e55f98) passed its original scanner probes, Release build, analyzer, and simulator tests in [hosted run 29457701562](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29457701562) |
| F5.1 — local-file ingress hardening | Verified | Implementation commit [`901508d`](https://github.com/Ayyitskevin/Hippocrates/commit/901508df17bb1a2577a721785d174c4bed403a56) passed 180 scanner checks, both planted boundary probes, Release build, analyzer, and simulator tests in [hosted run 29468180613](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29468180613) |
| F6 — configuration ownership enforcement | Verified | Implementation commit [`a47401c`](https://github.com/Ayyitskevin/Hippocrates/commit/a47401ce718acf76734c90a5740a189d30393997) passed 230 scanner checks, both planted boundary probes, Release build, analyzer, and simulator tests in [hosted run 29505198470](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29505198470) |
| F7 — backup completeness enforcement | Verified | Implementation commit [`7825f1c`](https://github.com/Ayyitskevin/Hippocrates/commit/7825f1cf2fc9d491a11ed734122b442206f6885c) passed 242 scanner checks, both planted backup-shape probes, Release build, analyzer, and simulator tests in [hosted run 29511769913](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29511769913) |
| F8 — immutable development-backup compatibility | Verified | Implementation commit [`6da9ef4`](https://github.com/Ayyitskevin/Hippocrates/commit/6da9ef497e55e443ad083b88c217979da6be9cb0) passed 255 scanner checks, both planted backup-contract probes, Release build, analyzer, and simulator tests in [hosted run 29515673481](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29515673481) |
| F9 — file-backed restore durability | Verified | Implementation commit [`dfa4593`](https://github.com/Ayyitskevin/Hippocrates/commit/dfa45931d7ff898b9ff90229b0211bc1a5955088) passed 255 scanner checks, both planted backup-contract probes, Release build, analyzer, and simulator tests in [hosted run 29517118694](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29517118694) |
| F10 — duplicate-identifier restore validation | Verified | Implementation commit [`2f48f95`](https://github.com/Ayyitskevin/Hippocrates/commit/2f48f950498776d270cc15f02e5ea93c7adbbf51) passed 255 scanner checks, both planted backup-contract probes, Release build, analyzer, and simulator tests in [hosted run 29518121878](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29518121878) |
| F11 — restore destination isolation | Verified | Implementation commit [`82d08da`](https://github.com/Ayyitskevin/Hippocrates/commit/82d08da4a8bb1f01f30fab7a6dac13084239975a) passed 255 scanner checks, both planted backup-contract probes, Release build, analyzer, and simulator tests in [hosted run 29519234311](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29519234311) |
| F12 — restore save-failure rollback | Verified | Implementation series through [`b01a491`](https://github.com/Ayyitskevin/Hippocrates/commit/b01a491cea6e9e5429851e27c2208ea3ed3982d2) passed 257 scanner checks, both planted backup-contract probes, Release build, analyzer, and simulator tests in [hosted run 29521705988](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29521705988) |
| F13 — restore validation isolation | Verified | Implementation commit [`403111d`](https://github.com/Ayyitskevin/Hippocrates/commit/403111d36882152530088e56f0a21c925a5b7b8e) passed 257 scanner checks, both planted backup-contract probes, Release build, analyzer, and simulator tests in [hosted run 29522864592](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29522864592) |
| F14 — nonnegative intervention duration | Verified | Implementation commit [`60f988a`](https://github.com/Ayyitskevin/Hippocrates/commit/60f988aff71e9bb6dfea0a16a7c0ec0b52b51dc9) passed 257 scanner checks, both planted backup-contract probes, Release build, analyzer, and 31 simulator tests in [hosted run 29523928066](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29523928066) |
| F15 — configuration creation save-failure rollback | Verified | Implementation commit [`078afad`](https://github.com/Ayyitskevin/Hippocrates/commit/078afad5a89f644a9199328e29b4d5a89a3a8c0b) passed 257 scanner checks, both planted backup-contract probes, Release build, analyzer, and 32 simulator tests in [hosted run 29524757883](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29524757883) |
| F16 — canonical backup record ordering | Verified | Implementation commit [`d64f7bd`](https://github.com/Ayyitskevin/Hippocrates/commit/d64f7bde3359c6734d58c737ee6a2583751c7096) passed 257 scanner checks, both planted backup-contract probes, Release build, analyzer, and 33 simulator tests in [hosted run 29529607273](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29529607273) |
| F17 — scanner-owned privacy-manifest semantics | Verified | Implementation commit [`ebf1f4e`](https://github.com/Ayyitskevin/Hippocrates/commit/ebf1f4e0484765f57a6497482ba3ee88210a5372) passed 270 scanner checks, both planted privacy-manifest probes, Release build, analyzer, and 33 simulator tests in [hosted run 29539042329](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29539042329) |
| R0 — RXcalc product/boundary pivot | Locally verified; hosted evidence pending | Product and architecture contracts, exact source identities, 288 scanner checks, and planted direct/sandboxed probe definitions are implemented |
| R1 — stateless RXcalc MVP | Implemented as draft; hosted and external gates pending | Searchable Cockcroft-Gault, 2021 CKD-EPI, adult BMI, and Mosteller BSA catalog with formula vectors, unit parity, input bounds, and visible draft limitations |
| D0 — product decisions | Closed | P-001 through P-006 accepted 2026-07-18 as user-owned choices via the owner pivot recorded in the [decision register](decision-register.md); I-005 is the remaining unrelated implementation decision |
| M1 — configuration and taxonomy ownership | Verified | Taxonomy service, starter set, first-run gate, and editors passed the hosted Release build, analyzer, boundary probes, and simulator tests on the merged head in [run 29646317092](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29646317092) |
| M2 — five-second capture and resolution ledger | Implemented | Capture, frecency ranking, and the I-013 ledger passed the hosted pipeline on the merged head in [run 29646789732](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29646789732); the real-device one-handed five-second acceptance run remains an open owner gate |
| M3 — summary and CSV export | Implemented | Summary engine, I-007 rate, deterministic CSV, Charts, and the reviewed ShareLink seam passed the hosted pipeline on the merged head in [run 29647799507](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29647799507); manager acceptance of the artifact remains an open owner gate |
| M4 — DI capture and de-identification gate | Verified | The scanner and fixtures passed in [run 29656090942](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29656090942); the vault, service-enforced gate, and full suite passed post-hotfix in [run 29657016108](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29657016108) after one test-only container-lifetime crash was fixed forward |
| M5 — freshness and retrieval | Verified | Freshness policy boundaries, one-tap re-verification, the staleness interstitial, and DI search passed on the exact merged head in [run 29657142388](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29657142388) |
| M6 — the compounding link | Verified | The intervention-to-DI link, year-aware aggregate, and the multi-year backup fixture passed the hosted pipeline on the merged head in [run 29659879056](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29659879056) |
| M7 — portfolio, restore, and reminders | Implemented | Backup export with the I-011 timestamp, the DI portfolio, the 90-day reminder, and the I-010 reviewed restore adapter with its exact-body pin and import gate passed the hosted pipeline across [run 29667549115](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29667549115) (7a) and the 7b merge; the clean-install export/restore acceptance run remains an open owner gate |
| Phase 8 — store readiness | Blocked on external gates | Store-listing, acceptance-script, and app-icon docs exist; app icon art, on-device acceptance, P-008/P-009, signing, and App Store submission remain owner/external gates |

## Milestone 0 — foundation evidence (complete)

Deliverables:

- macOS GitHub Actions workflow pinned to Xcode 16.4 / iOS 18.5;
- successful project discovery, source-boundary run, build, and hosted unit tests;
- fixes for any real SwiftData macro, project, resource, or test-host defect;
- a documented local Xcode acceptance command; and
- no signing, TestFlight, or App Store action.

Exit gate achieved: canonical `main` has a green hosted Apple Release build,
static analysis, simulator test run, and executable boundary probe. A Linux parse
remains a fast local check, not a substitute for this hosted evidence.

## Foundation hardening — configuration and backup evolution

Implemented deliverables:

- one main-actor `AppConfigService` that creates only from a clean context and
  exposes a no-save restore insertion path;
- `nil` policy state for unanswered DI staleness and cost values;
- one type-owned cost default with optional intervention snapshots, preserving
  unknown separately from explicit zero;
- backup format v2 plus an explicit development-format-v1 value-space migration;
- validation for negative cost, nonpositive staleness, freshness ordering, legacy
  key mismatches, and legacy duplicate-source conflicts; and
- in-memory, file-backed, round-trip, compatibility, and boundary-contract tests.

Exit gate achieved: implementation commit
[`ade0c7f`](https://github.com/Ayyitskevin/Hippocrates/commit/ade0c7fc53d480ee03360499f703fd6c87972d67)
passed the hosted Release build, analysis, simulator tests, and planted-networking
boundary probe.

## Foundation hardening — boundary-control hardening

Implemented deliverables:

- a linear, top-level PBX property parser that rejects duplicate, missing,
  malformed, or quoted-string-spoofed architecture keys;
- exact recursive disk-to-target equality for app/test Swift files, with duplicate,
  wrong-type, missing, escaped, cross-target canonical paths, and physical
  device/inode aliases rejected;
- an exact one-manifest app resource phase and empty test resource phase;
- exactly six bound Debug/Release configurations with allowlisted keys and pinned
  execution-sensitive values, plus one strict shared-scheme XML tree, no
  shadow user schemes, and no symbolic links anywhere in the project bundle;
- canonical-file privileges keyed only by exact normalized repository-relative
  paths, so basename and suffix collisions inherit no exception;
- closed source/import/interpolation allowlists covering transport, iCloud,
  implicit loaders, rich-text links, dynamic invocation, and encoding evasions;
- exact local-only app and test SwiftData construction seams with CloudKit
  explicitly disabled;
- literal-safe persisted-Intervention brace inspection; and
- 128 executable scanner checks, a direct recursive negative probe planting API,
  unlisted-source, extra-resource, test-loader, and configuration violations, and
  a separate sandboxed Xcode negative probe limited to declared inputs.

Exit gate achieved: the implementation series ending at
[`dda1ab8`](https://github.com/Ayyitskevin/Hippocrates/commit/dda1ab8c64c0b7979bd715a74511868be5e55f98)
passed the exact-head direct and sandboxed planted diagnostics, Xcode 16.4
Release build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29457701562](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29457701562).

## Foundation hardening — local-file ingress hardening

A post-verification review found that SwiftUI file pickers could supply an
inferred security-scoped URL and feed path/stream readers without matching the
original F5 rules. It also found alternate drop, paste, item-provider, and
external-activity ingress. No such shipping UI existed, but the control did not
yet enforce I-010's reviewed-adapter gate.

Implemented deliverables:

- file-picker, file-mover/exporter, document-browser, drop/paste/item-provider,
  external-activity, security-scoped/bookmark, coordinated-file, and additional
  ubiquity surfaces fail closed;
- reviewed Foundation collection/data/string loaders, contextual URL
  initializers, URL/path streams,
  FileHandle, FileWrapper, keyed-unarchive, and FileManager content/enumeration
  seams require explicit boundary review;
- the one bundled privacy-manifest path read is masked only for its exact
  normalized test-file identity, with suffix collisions rejected;
- scanner inventory increased from 128 to 180 executable checks; and
- both direct and sandboxed hosted probes plant one inferred file-picker chain
  with security-scope, path/stream reads, and external drop, then require each
  specific diagnostic.

Exit gate achieved: implementation commit
[`901508d`](https://github.com/Ayyitskevin/Hippocrates/commit/901508df17bb1a2577a721785d174c4bed403a56)
passed the exact-head direct/sandboxed diagnostics, Xcode 16.4 Release build,
static analysis, and iOS 18.5 simulator tests in
[hosted run 29468180613](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29468180613).

## Foundation hardening — configuration ownership enforcement

A red-team review showed that a spelling-only `AppConfig(` scanner rule could
not prove service ownership: Swift contextual initialization, aliases,
metatypes, extensions, and bound method references offer valid alternate forms.
The boundary now relies on compiler-enforced capability access for safe Swift,
reference-identity validation for the capability object, and source rejection
for unsafe memory, restricted SwiftData backing/direct-value mutations, and
unreviewed model deletion.

Implemented deliverables:

- `AppConfigService` owns the only instance of a final, checked-`Sendable`
  `Authority` class whose initializer is file-private;
- both `AppConfig` construction paths and its staleness mutator require that
  authority, validate its canonical object identity, and remove initializer
  defaults;
- exact normalized model/service identities pin the three persisted properties,
  initializer/mutator bodies and assignment semantics, two service constructions,
  two inserts, and one service mutation;
- app and test scans reject explicit authority, constructor, mutation, alias,
  metatype, shadow, extension, unsafe-memory, opaque-pointer,
  `PersistentModel.setValue`, and backing-data escape spellings; all model
  deletion is closed outside one exact pending-delete test fixture;
- scanner inventory increased from 180 to 230 executable checks;
- isolated self-tests relocate authority checks, mutate every protected
  right-hand side, reject literal-smuggled callable decoys and property
  observers, and exercise direct-value and model-lifecycle bypasses; and
- both hosted probes weaken the authority initializer and plant direct plus
  opaque-pointer/contextual construction, generated backing-data copying,
  direct-value mutation, and unreviewed deletion, then require every diagnostic.

No persisted property, schema version, migration, product default, or UI changed.

Implementation commit [`a47401c`](https://github.com/Ayyitskevin/Hippocrates/commit/a47401ce718acf76734c90a5740a189d30393997)
pass the exact-head direct/sandboxed diagnostics, Xcode 16.4 Release build,
static analysis, and iOS 18.5 simulator tests in
[hosted run 29505198470](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29505198470).

## Foundation hardening — backup completeness enforcement

A backup round-trip can agree with itself even when both export and restore omit
the same newly persisted field. F7 therefore uses independent surfaces rather
than treating archive equality alone as completeness proof.

Implemented deliverables:

- live SwiftData metadata is reconciled with an explicit no-ignored-field
  manifest covering every `SchemaV1` stored property;
- each property maps to a same-model record value, a foreign UUID, an explicit
  inverse, or the reviewed `AppConfig.singletonKey == "app"` reconstruction;
- a populated fixture constructs the complete expected archive independently of
  the exporter, and restored models receive direct field-by-field assertions;
- synthesized `Codable` record/type decoding remains separate from
  `BackupService.validate(_:)` graph and domain checks; and
- the Linux scanner plus both hosted probes fail closed on planted persisted
  fields and custom-`Codable` archive drift with dedicated diagnostics.

No persisted field, schema version, migration, backup format, product default,
or UI changed.

Verification: implementation commit [`7825f1c`](https://github.com/Ayyitskevin/Hippocrates/commit/7825f1cf2fc9d491a11ed734122b442206f6885c)
passed both planted diagnostics, all 242 scanner checks, the Xcode 16.4 Release
build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29511769913](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29511769913).

## Foundation hardening — immutable development-backup compatibility

The original format-v1 migration borrowed five mutable current-format record
types even though the architecture described the decoder as immutable. That
created latent compatibility coupling: a future v2 record edit could silently
change which historical JSON format v1 accepts. F8 makes the historical shape a
format-owned contract instead of a documentation promise.

Implemented deliverables:

- the private format-v1 decoder owns exact let-only records for its outer archive,
  payload, and all seven historical model representations;
- every historical field maps explicitly into format v2, including the intended
  widening of intervention cost and staleness values to optional current fields;
- normalized UUID aliases in the legacy cost map coalesce only when their values
  agree and fail loudly on conflict without a duplicate-key trap;
- one literal format-v1 fixture covers every historical field, all frozen enum
  values, mixed optional state, every forward UUID relationship, inverse recovery,
  validation, restore, direct destination assertions, and deterministic re-export;
- the source scanner rejects shape, type, mutability, default, current-DTO reuse,
  custom-decoding, member, nested-declaration, and extension drift; and
- both hosted negative probes plant a fail-loud format-v1 mutation and require the
  dedicated immutable-compatibility diagnostic.

No persisted field, schema version, backup JSON shape, product default, UI,
network surface, or distribution setting changed.

Verification: implementation commit [`6da9ef4`](https://github.com/Ayyitskevin/Hippocrates/commit/6da9ef497e55e443ad083b88c217979da6be9cb0)
passed both planted backup-contract probes, all 255 scanner checks, the Xcode 16.4
Release build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29515673481](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29515673481).

## Foundation hardening — file-backed restore durability

The existing tests separately proved a complete restore in memory and persisted
model relationships across a file-backed close/reopen. Neither proved that
`BackupService.restore` commits a complete archive that survives container
teardown without a caller-side save. F9 adds that missing composition test; it
does not expose backup import or restore UI.

Implemented deliverables:

- an independently constructed current-format archive populates all seven model
  representations, every scalar and optional field, and all five forward UUID
  relationships;
- the archive restores through the existing local-only file-backed test seam,
  requires a clean context without a caller-side save, and releases the first
  container before reopening the same store; and
- the reopened store must exactly re-export the archive, contain one of each
  model, rebuild both DI inverse relationships, and reconstruct the canonical
  `AppConfig.singletonKey`.

No shipping source, persisted field, schema version, migration, backup format,
product default, UI, network surface, or distribution setting changed.

Verification: implementation commit [`dfa4593`](https://github.com/Ayyitskevin/Hippocrates/commit/dfa45931d7ff898b9ff90229b0211bc1a5955088)
passed both planted backup-contract probes, all 255 scanner checks, the Xcode 16.4
Release build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29517118694](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29517118694).

## Foundation hardening — duplicate-identifier restore validation

Duplicate identifiers were rejected by validation, but test coverage did not
exercise every identifier-bearing archive array through the restore entry point
or prove that rejection leaves the destination untouched. F10 closes that
evidence gap without changing restore behavior.

Implemented deliverables:

- all six identifier-bearing backup arrays independently receive a duplicate
  record and execute through `BackupService.restore`;
- every case requires the exact duplicate-identifier entity and UUID; and
- each rejected restore leaves a fresh destination at zero records across all
  seven models with no pending context changes.

Only `BackupRoundTripTests.swift` changed. No shipping source, persisted field,
schema version, migration, backup format, product default, UI, network surface,
or distribution setting changed.

Verification: implementation commit [`2f48f95`](https://github.com/Ayyitskevin/Hippocrates/commit/2f48f950498776d270cc15f02e5ea93c7adbbf51)
passed both planted backup-contract probes, all 255 scanner checks, the Xcode 16.4
Release build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29518121878](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29518121878).

## Foundation hardening — restore destination isolation

Restore already rejected a nonempty destination or a context with pending
changes, but coverage exercised only one saved model type and pending inserts and
deletes. F11 expands that evidence across the complete destination surface and an
unsaved update without changing restore behavior.

Locally verified deliverables:

- each of the seven persisted model types independently exercises the existing
  nonempty-destination guard through `BackupService.restore`;
- every saved-destination rejection returns `destinationNotEmpty`, leaves the
  context clean, and preserves exact archive equality before and after the
  attempted restore; and
- a pending update returns `destinationHasPendingChanges` while preserving its
  unsaved field values and pending-change state.

Only `BackupRoundTripTests.swift` changed. No shipping source, persisted field,
schema version, migration, backup format, product default, UI, network surface,
or distribution setting changed.

Verification: implementation commit [`82d08da`](https://github.com/Ayyitskevin/Hippocrates/commit/82d08da4a8bb1f01f30fab7a6dac13084239975a)
passed both planted backup-contract probes, all 255 scanner checks, the Xcode 16.4
Release build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29519234311](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29519234311).

## Foundation hardening — restore save-failure rollback

`BackupService.restore` rolled its context back after a save error, but no test
forced a complete archive past validation and insertion into that catch path.
F12 adds this failure-path evidence without changing restore behavior or exposing
restore UI.

Implemented deliverables:

- the complete current-format seven-model archive attempts restore into a
  pre-created file-backed test store with saving disabled;
- `ModelContext.willSave` observes all seven pending inserts, proving the forced
  failure occurs at the save boundary; and
- the thrown storage error leaves no pending inserts, updates, or deletes; the
  failed dedicated context is discarded, and a later writable reopen confirms
  all seven model counts remain zero with no durable residue.

`BackupService` now documents that callers discard a failed dedicated restore
context. No shipping behavior, persisted field, schema version, migration, backup
format, product default, UI, network surface, or distribution setting changed.

Verification: implementation series through [`b01a491`](https://github.com/Ayyitskevin/Hippocrates/commit/b01a491cea6e9e5429851e27c2208ea3ed3982d2)
passed both planted backup-contract probes, all 257 scanner checks, the Xcode 16.4
Release build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29521705988](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29521705988).
The hosted log contains no `vnode unlinked` or `invalidated open fd` cleanup
diagnostics.

## Foundation hardening — restore validation isolation

Existing tests covered these validation branches directly or with narrower
fixtures, but restore-level coverage did not isolate all six boundary cases or
consistently prove that rejection leaves the destination untouched. F13 closes
that evidence gap without changing restore behavior.

Implemented deliverables:

- six independent fixtures exercise a negative intervention cost, negative
  configured staleness, a verification history ending at the wrong date, equal
  adjacent history dates, a review date equal to verification, and a populated
  unsupported format version through `BackupService.restore`;
- every case requires its exact `BackupError`, including the associated entity,
  identifier, version, or invalid value; and
- each rejected restore leaves a fresh destination at zero records across all
  seven models with no pending context changes.

Only test coverage changed. No shipping source, persisted field, schema version,
migration, backup format, product default, UI, network surface, or distribution
setting changed.

Verification: implementation commit [`403111d`](https://github.com/Ayyitskevin/Hippocrates/commit/403111d36882152530088e56f0a21c925a5b7b8e)
passed both planted backup-contract probes, all 257 scanner checks, the Xcode 16.4
Release build, static analysis, and iOS 18.5 simulator tests in
[hosted run 29522864592](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29522864592).

## Foundation hardening — nonnegative intervention duration

`minutesSpent` is optional and its capture placement remains gated, but a
negative duration is not a meaningful ledger value. Backup validation previously
accepted that impossible value from both a live store and a supplied archive.

Implemented deliverables:

- `BackupService` rejects a negative intervention duration with the exact
  intervention identifier and invalid value;
- export of a persisted negative duration fails without changing the source;
- restore of a complete archive carrying a negative duration fails before the
  fresh destination changes; and
- unknown (`nil`), explicit zero, and positive durations remain valid.

Only backup validation, its tests, and documentation changed. No persisted field,
schema version, migration, backup format, product default, UI, network surface,
or distribution setting changed.

Verification: implementation commit [`60f988a`](https://github.com/Ayyitskevin/Hippocrates/commit/60f988aff71e9bb6dfea0a16a7c0ec0b52b51dc9)
passed both planted backup-contract probes, all 257 scanner checks, the Xcode 16.4
Release build, static analysis, and 31 iOS 18.5 simulator tests in
[hosted run 29523928066](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29523928066).

## Foundation hardening — configuration creation save-failure rollback

`AppConfigService.fetchOrCreate` requires a clean context and rolls back the
configuration insert it owns when saving fails, but runtime coverage exercised
only successful/idempotent creation and dirty-context refusal. F15 forces the
ordinary creation path through its save-error catch without changing
configuration behavior or product policy.

Implemented deliverables:

- a pre-created empty file-backed store is reopened with saving disabled and
  autosave explicitly off;
- `ModelContext.willSave` observes exactly one pending `AppConfig`, proving the
  forced failure reaches the save boundary;
- the underlying storage error propagates while rollback clears pending inserts,
  updates, and deletes; and
- the failed context is discarded before a writable reopen proves all seven
  model counts remain zero with no durable residue.

Only test coverage and roadmap evidence changed. No shipping source, persisted
field, schema version, migration, backup format, product default, UI, network
surface, or distribution setting changed.

Verification: implementation commit [`078afad`](https://github.com/Ayyitskevin/Hippocrates/commit/078afad5a89f644a9199328e29b4d5a89a3a8c0b)
passed both planted backup-contract probes, all 257 scanner checks, the Xcode 16.4
Release build, static analysis, and 32 iOS 18.5 simulator tests in
[hosted run 29524757883](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29524757883).
The hosted log contains no `vnode unlinked` or `invalidated open fd` cleanup
diagnostics.

## Foundation hardening — canonical backup record ordering

`BackupService.makeArchive` already sorted every UUID-bearing top-level record
array, but the operations were distributed across the exporter and the tests did
not independently prove each sort. SwiftData fetch order is unspecified, so
opposite insertion order alone cannot serve as the regression oracle. F16 moves
the existing transforms into one pure value canonicalizer and tests that seam
directly without changing emitted backup semantics.

Implemented deliverables:

- store export canonicalizes intervention types, drug classes, service lines,
  interventions, questions, and citations by UUID before validation and encoding;
- a direct reversed-payload assertion makes removal of any one of the six sorts
  fail independently of SwiftData fetch behavior; and
- two equivalent stores created with opposite insertion and relationship-
  assignment orders must produce the same canonical archive and encoded bytes.

Only export implementation structure, regression coverage, and architecture and
roadmap evidence changed. No persisted field, schema version, migration, backup
format or bytes for an equivalent store, validation rule, product default, UI,
network surface, or distribution setting changed.

Verification: implementation commit [`d64f7bd`](https://github.com/Ayyitskevin/Hippocrates/commit/d64f7bde3359c6734d58c737ee6a2583751c7096)
passed both planted backup-contract probes, all 257 scanner checks, the Xcode 16.4
Release build, static analysis, and 33 iOS 18.5 simulator tests in
[hosted run 29529607273](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29529607273).
The hosted log specifically records
`testBackupExportOrderingIsCanonicalAcrossInsertionOrders` as passed.

## Foundation hardening — scanner-owned privacy-manifest semantics

Before F17, the build control proved that `PrivacyInfo.xcprivacy` was the only
app resource but left its meaning to one discoverable XCTest. An isolated copy
showed that renaming that test method and enabling tracking still passed all 257
scanner checks and the repository build check.

Implemented deliverables:

- the repository semantic pass parses the canonical manifest independently of
  PBX topology and XCTest discovery;
- `XMLParser` requires XML with exactly one immediate root declaration for each
  allowed key, `PropertyListSerialization` requires the exact two-key dictionary,
  and a typed `PropertyListDecoder` requires Boolean `false` tracking and an empty
  collected-data array without NSNumber/Bool bridge ambiguity;
- binary and malformed property lists, non-dictionary roots, missing or duplicate
  keys, tracking enabled, numeric lookalikes, nonempty collected data, tracking
  domains, and accessed-API declarations fail one stable diagnostic;
- scanner inventory increases from 257 to 270 executable checks, including the
  real file wrapper; and
- the bundled-resource XCTest repeats exact key cardinality and typed values,
  while both hosted probes use an anchored tracking mutation and require the
  scanner-owned diagnostic.

Only the scanner, its executable probes, bundled-resource test coverage, and
documentation changed. The shipping privacy manifest, app behavior, persisted
schema, backup format, product policy, UI, network surface, and distribution
settings did not change.

Verification: implementation commit [`ebf1f4e`](https://github.com/Ayyitskevin/Hippocrates/commit/ebf1f4e0484765f57a6497482ba3ee88210a5372)
passed both planted privacy-manifest probes, all 270 scanner checks, the Xcode
16.4 Release build, static analysis, and 33 iOS 18.5 simulator tests in
[hosted run 29539042329](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29539042329).
The hosted log specifically records
`testAppPrivacyManifestDeclaresNoTrackingAndNoCollectedData` as passed.

## Feature-specific decision gate

The 2026-07-18 owner pivot closed P-001 through P-006 as user-owned choices.
Their accepted rows in the [decision register](decision-register.md) bind the
affected features: a first-run responsibility notice, an explicitly offered and
skippable starter taxonomy, user-entered cost defaults, a visible summary range
defaulting to the current calendar year, a required per-user staleness choice,
and the unchanged frozen DI vocabulary.

I-003, I-004, I-007, I-008, I-009, I-011, I-012, and I-013 are likewise
accepted and bind their features as recorded. Before the affected feature
ships, still resolve I-005 (verification provenance) and I-010 (local-file
import boundary).

## Milestone 1 — configuration and taxonomy ownership

Deliverables:

- reuse the policy-neutral `AppConfigService` implemented in foundation hardening;
- an explicit first-run configuration gate, after which ordinary launches go
  directly to capture with no dashboard or recurring welcome screen (guarded
  restore joins this pre-bootstrap gate only in Milestone 7);
- empty editable intervention types, drug classes, and service lines;
- soft-deactivation instead of deletion for referenced taxonomy rows;
- cost defaults represented once and left empty unless P-002 supplies values;
- deterministic ordering and validation; and
- backup coverage for every configuration mutation.

Exit gate: a clean install contains no invented categories or dollar values, the
user can configure all three taxonomies, and backup round-trip remains lossless.

## Milestone 2 — five-second capture

Deliverables:

- launch directly into bottom-anchored type → class → acceptance controls;
- bounded, deterministic frecency ordering;
- default cost prefill and one-tap override;
- reviewed optional placement for service line, minutes, and cost override that
  adds no required tap to the three-tap path;
- save on the third tap with light haptic feedback;
- one five-second undo snackbar and no modal confirmation;
- aggregate filters only—no intervention detail/search screen; and
- performance instrumentation usable in tests without shipping analytics.

Exit gate: the pilot user logs ten representative interventions one-handed on
their own phone in airplane mode, with every entry under five seconds. Simulator
timing does not close this gate.

## Milestone 3 — summary and TestFlight Build 1

Deliverables:

- selectable date range using the P-004 default;
- counts by type/month, acceptance rate, cost total, top drug classes, and
  service-line breakdown;
- acceptance-rate computation using the approved I-007 denominator, labeled in
  the artifact;
- deterministic RFC 4180 CSV export with spreadsheet formula-injection defense;
- printable Swift Charts summary; and
- real data review with the pilot user.

Exit gate: the pilot user would hand the output to their manager without
editing. TestFlight
submission occurs only after explicit approval; stop and collect feedback before
starting DI UI.

## Milestone 4 — DI capture and de-identification gate

Deliverables:

- durable multi-step draft;
- structured question/background/classification/search/response/reference/follow-up;
- structured citations by tier;
- an approved design for tags, citation metadata, taxonomy labels, and any other
  editable string that could become an indirect identifier channel;
- required editable `verifiedOn` and derived `reviewAfter`;
- regex fixtures for every specified identifier pattern;
- blocking field/range review with Remove or Not an identifier; and
- the same guard in backup import before restore is exposed.

Exit gate: MRN, date, room, phone, age-over-89, and literal fixtures block; no
finding is silently scrubbed or permanently ignored; clean drafts save offline.

## Milestone 5 — freshness and retrieval

Deliverables:

- one pure freshness policy in which `answeredAt == nil` returns draft before any
  green/amber/red state;
- a per-record red threshold one additional `reviewAfter - verifiedOn` interval
  after `reviewAfter`, unaffected by later default changes;
- answer interstitial before every amber/red detail presentation;
- one-tap re-verification with append-only history;
- in-memory lowercased DI full-text search; and
- freshness badges in every result row.

Exit gate: boundary-date tests cover both interval transitions and a red record
cannot render with green styling or bypass the interstitial.

## Milestone 6 — the compounding link

Deliverables:

- “this raised a question” creates and links a DI draft;
- DI detail shows linked interventions and year-aware aggregate language;
- delete rules preserve interventions if a question is removed; and
- backup round-trip preserves both directions without duplicate links.

Exit gate: a restored fixture proves one DI answer can accumulate interventions
across years and both navigation directions remain correct.

## Milestone 7 — portfolio, restore, and reminders

Deliverables:

- formatted DI portfolio export in standard response order;
- user-facing full-backup import under the reviewed pristine/replacement policy
  and the narrow security-scoped local-file URL adapter in I-010;
- one-time best-effort backup note that honestly states iOS cannot reliably report
  whether device/iCloud backup is enabled;
- dismissible reminder when `lastExportAt` exceeds 90 days.

The reminder uses the single event definition approved in I-011 and never calls
archive generation or share-sheet presentation confirmed delivery. Summary and
DI-portfolio exports do not update this backup timestamp.

Exit gate: export/import is exercised on a clean device/simulator installation,
re-export is logically identical, and no raw DI text can bypass the guard.


## RXcalc delivery track

The canonical slice plan is [`rxcalc-plan.md`](rxcalc-plan.md).

- R0 replaces the former no-calculation doctrine with an exact stateless RXcalc
  exception and scanner/CI controls for source identity, persisted state,
  division seams, calculation/equation types, and dose-selection declarations.
- R1 supplies the searchable draft catalog, Cockcroft-Gault, 2021 CKD-EPI
  creatinine eGFR, CDC metric adult BMI for age 20 or older, and Mosteller BSA.
  Sources are independently identified, unit systems are equivalent, changing a
  unit clears the affected numeric entry, locale decimal separators are accepted,
  and age/overflow failures are explicit.
- R2-R4 are unstarted hypotheses outside the current v1 commitment. Drug-specific
  clinical content is outside the product, not an approved later slice.

R1 engineering exit requires 288 portable scanner checks, planted direct and
sandboxed RXcalc violations, an exact-head Xcode Release build and analyzer, and
all simulator tests including official NKF vectors. Real-device acceptance,
immutable P-008 clinical approval, P-009 regulatory/claims review, and explicit
owner distribution authorization are separate gates. Until they close, every
R1 descriptor and result remains visibly draft.

## V1 completion audit

A distributable product needs direct evidence for: exact-head hosted build,
analyzer, tests, and planted boundary rejection; persisted-schema privacy;
backup compatibility and logical equality; approved summary semantics and
manager acceptance; freshness/de-identification/import behavior; manifest
consistency; and the bounded, source-versioned, stateless RXcalc slice.

Real-device capture and RXcalc acceptance exercises, institutional permission,
immutable P-008 clinical approval, P-009 regulatory/claims review, owner-authorized
TestFlight/App Store actions, and the external privacy label remain visibly open
until observed. Engineering evidence never closes those gates.

## V1 product execution (2026-07-18 pivot)

The 2026-07-18 owner pivot re-scoped Hippocrates as a free, general-audience app
for hospital pharmacists. The now-executed ledger/DI Phase 0-8 plan is preserved
as a dated snapshot in [`opus-execution-plan.md`](opus-execution-plan.md), with
its motivating review in [`pharmacist-review.md`](pharmacist-review.md).
Milestones 1-7 above remain the ledger/DI specification. The live RXcalc sequence
and gates are this roadmap plus [`rxcalc-plan.md`](rxcalc-plan.md).

### v1 feature completion (2026-07-19)

All ledger/DI v1 feature phases are implemented and merged to `main` with hosted
CI evidence recorded above: first-run and taxonomy ownership, capture and the
resolution ledger, summary/CSV, the DI vault and de-identification gate,
freshness and search, the intervention-to-DI link, and backup/portfolio/restore.
There is no remaining ledger/DI v1 feature code. RXcalc R1 is a separate newly
implemented draft slice; its later slices and external gates remain open.

The open release gates are human or external, not hidden engineering claims:

- app icon artwork and its reviewed asset-catalog PR
  ([`app-icon.md`](app-icon.md));
- the full on-device acceptance run
  ([`acceptance-scripts.md`](acceptance-scripts.md)), including RXcalc locale,
  invalidation, non-retention, and vector exercises;
- manager acceptance of the summary artifact and clean-install restore evidence;
- institutional permission for shift use (each user's responsibility, P-001);
- immutable P-008 clinical approval and P-009 regulatory/claims determination
  for the exact RXcalc release content; and
- explicit owner authorization for TestFlight/App Store submission and publication
  of the **Data Not Collected** privacy label
  ([`store-listing.md`](store-listing.md)).

## Permanent stop conditions

Stop implementation and escalate if a request introduces networking, CloudKit,
an account/server, patient identifiers, intervention free text, a clinical
formula outside the reviewed RXcalc boundary, dose/result/treatment
recommendations, unversioned or unapproved clinical content, hospital
reference/protocol storage, third-party packages, notifications/analytics, or
any post-v1 product surface before its explicit decision and evidence gate.
