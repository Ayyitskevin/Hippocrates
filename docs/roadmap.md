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
| F4 — policy-neutral configuration and backup evolution | Implemented; hosted verification pending | One configuration owner, unknown/zero separation, strict DI chronology, and backup v2/v1 migration require exact-head hosted CI |
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
- backup format v2 plus an immutable development-format-v1 value-space migration;
- validation for negative cost, nonpositive staleness, freshness ordering, legacy
  key mismatches, and legacy duplicate-source conflicts; and
- in-memory, file-backed, round-trip, compatibility, and boundary-contract tests.

The exit gate closes only when the exact canonical commit passes hosted Release
build, analysis, simulator tests, and the planted-networking boundary probe.

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
