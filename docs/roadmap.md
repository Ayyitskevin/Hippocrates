# Delivery roadmap

The build order is a dependency graph, not a list of equally parallel features.
Schema and backup protect the asset; configuration enables capture; real capture
data informs later ergonomics. Work may be parallelized only when it does not
cross a decision or evidence gate.

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
| D0 — Jenn decisions | Awaiting answers | P-001 through P-006 recorded in `decision-register.md`; affected product features remain gated |

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

## Feature-specific decision gate

P-001 gates use on shift, not local foundation work. P-002 gates entry of nonnil
cost defaults; P-003 and I-004 gate taxonomy seeds and editor behavior; P-004
gates the default summary range; P-005 gates DI freshness defaults; and P-006
gates the frozen DI vocabulary and its UI. If answers are unavailable, continue
only foundation hardening, tests, documentation, and non-product-specific tooling.

Before the affected feature ships, also resolve I-003 (restore readiness), I-004
(editable taxonomy identifier risk), I-005 (verification provenance), I-007
(acceptance denominator), I-008 (optional capture controls), I-009 (metadata
identifier channels), I-010 (local-file import boundary), I-011 (`lastExportAt`
semantics), and I-012 (bootstrap readiness). These implementation decisions are
not substitutes for Jenn's unanswered P-001 through P-006.

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

Exit gate: Jenn logs ten representative interventions one-handed on her own phone
in airplane mode, with every entry under five seconds. Simulator timing does not
close this gate.

## Milestone 3 — summary and TestFlight Build 1

Deliverables:

- selectable date range using the P-004 default;
- counts by type/month, acceptance rate, cost total, top drug classes, and
  service-line breakdown;
- acceptance-rate computation using the approved I-007 denominator, labeled in
  the artifact;
- deterministic RFC 4180 CSV export with spreadsheet formula-injection defense;
- printable Swift Charts summary; and
- real data review with Jenn.

Exit gate: Jenn would hand the output to her manager without editing. TestFlight
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

## V1 completion audit

Product v1 is complete only with direct evidence for: exact-head hosted build,
analysis, and tests; planted-network rejection; persisted schema privacy; backup
compatibility and logical equality; approved summary semantics and manager
acceptance; freshness boundaries; de-identification fixtures and import parity;
privacy-manifest consistency; and absence of clinical calculation or
recommendation paths. The real-device five-second test, institutional permission
for shift use, TestFlight/App Store actions, and the App Store privacy label are
human/external gates and remain visibly open until observed.

## Permanent stop conditions

Stop implementation and escalate if a request introduces networking, CloudKit,
an account/server, patient identifiers, intervention free text, a clinical
calculation or recommendation, hospital reference/protocol storage, third-party
packages, notifications/analytics, or any post-v1 product surface before usage
data from product v1 defines it.
