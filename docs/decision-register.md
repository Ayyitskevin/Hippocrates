# Decision register

This register separates product facts that only the owner can decide from
implementation decisions the repository owner can make. Pending product facts
are never filled with plausible defaults and never silently converted into
requirements. On 2026-07-18 the owner re-scoped Hippocrates as a free,
general-audience app for hospital pharmacists; the former single-user product
gates closed as the user-owned choices recorded below.

## Accepted architecture decisions

| ID | Decision | Consequence |
|---|---|---|
| A-001 | `Intervention` and `DIQuestion` remain separate models | Their capture, retrieval, and lifecycle semantics cannot collapse into a generic `Entry` |
| A-002 | One local SwiftData store, explicitly versioned from V1 | Every released schema is retained; migrations receive explicit review |
| A-003 | No network layer and zero SPM dependencies | Offline behavior is ordinary behavior; external SDKs cannot enter incidentally |
| A-004 | `Intervention` uses an exact persisted-property allowlist with no text | Adding any property is an architecture review, not a casual model edit |
| A-005 | Full backup uses value DTOs and portable UUID relationships | SwiftData store-local identifiers never become backup identity |
| A-006 | DI freshness is computed per record, while verification history is durable | Draft overrides color; red uses a second `reviewAfter - verifiedOn` interval; review dates and history are strictly increasing; re-verification never erases history |
| A-007 | DI search filters in memory | The expected data volume is small and this avoids fragile SwiftData string predicates |
| A-008 | GitHub macOS CI validates Xcode 16.4 and iOS 18.5 | Linux development cannot be mistaken for Apple-platform verification |
| A-009 | TestFlight/App Store submission is a human action | Autonomous development does not imply autonomous distribution |
| A-010 | CSV output follows RFC 4180 and neutralizes spreadsheet formula cells | Manager exports remain portable without letting editable labels become executable spreadsheet input |
| A-011 | iOS backup-state messaging is explicitly best-effort | No public API reliably proves device/iCloud backup state, so the app never claims it verified enabled/disabled status |
| A-012 | `AppConfigService` is the only configuration-row owner | Its file-private authority is identity-checked by every model initializer and mutator; exact model initializer/mutator bodies and reviewed service seams are pinned, while direct SwiftData value/backing mutation and unreviewed model deletion are source-forbidden; main-actor fetch-or-create requires a clean context, while restore inserts without saving inside its own transaction |
| A-013 | Type-owned defaults and optional intervention snapshots are the only cost representation | Unknown/unassigned remains `nil`, explicit zero remains zero, and no app-wide duplicate map exists |
| A-014 | Backup format dispatch and migration happen in value space | Format v2 is current; development-format v1 owns private let-only historical records, never reuses current-format DTOs, explicitly maps every field before validation or store mutation, and rejects conflicts |
| A-015 | RXcalc is a stateless feature boundary beside the ledger store | Calculator inputs/results never enter SwiftData, backup, logs, analytics, or free text; the scanner rejects persistence coupling and clinical calculator types elsewhere |
| A-016 | Every RXcalc formula and source has a stable version identifier and dated provenance | Content changes create a new reviewed identifier and golden evidence; combined views retain separate formula/source identities |

## Accepted product decisions

A P-ID enters this table only after the named owner or institutional authority
reviews an explicit answer.

| ID | Decision | Deciding authority role | Decision date | Non-sensitive provenance | Implementation consequence |
|---|---|---|---|---|---|
| P-001 | Institutional permission is each user's own responsibility, affirmed through a first-run notice; the app never claims to verify hospital policy | Owner (product) | 2026-07-18 | Owner-directed pivot merged in PR #1 (`docs/opus-execution-plan.md`) | First-run shows a responsibility notice; the store listing carries the same disclaimer; no institutional gate blocks development |
| P-002 | No official cost-avoidance values ship; users may enter their institution's figures per intervention type | Owner (product) | 2026-07-18 | Owner-directed pivot merged in PR #1 | Defaults remain `nil`; zero never substitutes for unknown; exports label figures as user-configured estimates |
| P-003 | Taxonomies ship empty plus an explicitly offered, reviewable, skippable ASHP-derived starter set at first run | Owner (product) | 2026-07-18 | Owner-directed pivot merged in PR #1 | No silent seeding; the starter list ships as a reviewed Swift constant, not a bundled resource |
| P-004 | The summary range is a visible user control whose initial state is the current calendar year; the last selection is remembered | Owner (product) | 2026-07-18 | Owner-directed pivot merged in PR #1 | No hidden fixed cadence ships |
| P-005 | The DI staleness interval is a required per-user choice (6, 12, or custom months) at first DI use | Owner (product) | 2026-07-18 | Owner-directed pivot merged in PR #1 | `AppConfig.stalenessIntervalMonths` stays `nil` until the user chooses; no hidden default ships |
| P-006 | The frozen DI requestor, question-class, urgency, and source-tier vocabulary ships unchanged | Owner (product) | 2026-07-18 | Owner-directed pivot merged in PR #1 | Raw values remain persistence identifiers; every enum retains its `other` escape hatch |
| P-007 | Add RXcalc as a clean, stateless, source-versioned formula surface beside the ledger, beginning with the bounded R1 adult renal/body-size slice; it never selects inputs or doses, interprets results, recommends therapy, or carries protocol/drug content | Owner (product) | 2026-07-19 | Owner-directed RXcalc planning and implementation request; scope recorded in `docs/rxcalc-plan.md` | R1 may be engineered as visibly draft; clinical, device, regulatory/claims, and distribution gates remain independent |

## Accepted implementation decisions

| ID | Resolution |
|---|---|
| I-001 | `InterventionType.defaultCostAvoidanceCents` is the single configurable source; each intervention stores an optional historical snapshot |
| I-002 | One main-actor `AppConfigService` owns lookup, clean-context creation, validation, transactional restore insertion, and the canonical identity-checked authority required for model construction and mutation; unreviewed model deletion remains closed at the source boundary |
| I-006 | Decode each supported backup version explicitly and migrate value DTOs before store mutation |
| I-003 | v1 restore is offered only pre-bootstrap or into a logically pristine store; destructive replacement of a store containing user records is out of v1 |
| I-007 | Acceptance rate = accepted ÷ (accepted + rejected); pending and not-applicable are excluded from the denominator; all four counts are always displayed and exported beside the rate, and artifacts state the rule in text |
| I-008 | Optional service-line, minutes, and cost-override controls live in a collapsed strip above the three required capture controls; the collapsed state applies defaults and the required path stays exactly three taps; post-save corrections go through the I-013 ledger |
| I-011 | `lastExportAt` records the successful generation of a full-backup archive handed to the share sheet; reminder copy says "last backup created", never delivered or verified; summary and DI-portfolio exports never update it |
| I-012 | Capture is possible when at least one active intervention type and one active drug class exist; service lines are optional; first-run records the user's explicit onboarding choice, distinguishing never-configured from intentionally-minimal |
| I-013 | A bounded recent-interventions ledger permits structured-field edits, acceptance updates, and confirmed deletion through one reviewed service; it never offers free text or narrative; the no-detail-screen doctrine is amended to "no narrative detail screen" |
| I-004 | Taxonomy labels are single-line, trimmed, at most 60 characters, and unique per taxonomy, enforced by `TaxonomyService`; they are generic department categories, editor UI carries that purpose guidance, per-intervention category creation stays forbidden, and labels join the Phase 4 identifier-scan surface before backup-export UI ships |
| I-009 | Citation titles and locators are single-line, at most 200 characters, and pass through the same de-identification gate as the four guarded DI fields, enforced by `DIQuestionService`; tags are scanned on the archive-import surface, and a tags editor ships only with the same constraints and gate |
| I-010 | One exact-body-pinned `BackupImportAdapter` owns local-file ingress; it requires `isFileURL`, acquires security-scoped access, immediately captures `Data`, releases access, and exposes no remote/open/share path |
| I-014 | RXcalc is a post-first-run tab beside the ledger; its catalog, inputs, and results remain transient, and scanner exceptions are limited to exact source identities and reviewed formula-division seams |

## Pending product decisions — required before affected features

| ID | Owner | Question | Safe state until answered |
|---|---|---|---|
| P-008 | Independent qualified clinical reviewers | Are the exact four R1 formula versions, sources, units, rounding rules, limitations, test evidence, and displayed claims approved for the reviewed build and a stated review cadence? | Every descriptor remains `.draft`; no clinical/field use, TestFlight, App Store, or other distribution |
| P-009 | Owner with qualified regulatory/claims review | What regulatory posture and exact user-facing claims are appropriate for a release that includes the approved RXcalc formulas? | Store copy is provisional and no distribution submission occurs |

P-008 uses a two-phase, immutable transition rather than asking a commit to
approve itself:

1. Reviewers sign the exact **draft candidate commit**, a digest of the RXcalc
   source/evidence bundle, the proposed approved-status copy, their roles, date,
   disposition, and cadence for `cockcroft_gault_1976@1.0.0`,
   `ckd_epi_creatinine_2021@1.0.0`, `body_mass_index_cdc_metric@1.0.0`, and
   `body_size_mosteller_1987@1.0.0`.
2. An activation commit may change only review-status/provenance metadata to the
   pre-reviewed copy; it cannot alter a formula, source, unit conversion, rounding
   policy, limitation, or other displayed clinical claim.
3. An independent release verifier recomputes the signed digest, confirms that
   status-only diff, and appends the exact activation commit hash to the P-008
   record before any distribution.

Any other change or digest mismatch keeps/returns the affected descriptor to
`.draft` and requires a new review. P-008 clinical approval does not answer P-009.

### D0 closure record (2026-07-18)

P-001 through P-006 closed together when the owner re-scoped Hippocrates as a
free, general-audience app for hospital pharmacists. For each P-ID: disposition
`answered`; deciding authority `owner (product)`; decision date `2026-07-18`;
non-sensitive provenance the merged plan PR #1 (`docs/opus-execution-plan.md`
and `docs/pharmacist-review.md`). The answers are the accepted rows above.
P-007 and the pending P-008/P-009 gates are a separate RXcalc track; they are
not part of the D0 worksheet or its 2026-07-18 closure.

The worksheet mechanism remains canonical for any future product decision: a
disposition, an exact answer, a deciding authority role, an ISO `YYYY-MM-DD`
date, and non-sensitive provenance are all required, and a partial answer
leaves the safe state in force.

P-006's approved raw vocabulary is the four frozen groups in
`Hippocrates/Models/DomainEnums.swift` (requestor role, DI question class,
urgency, source tier). Renaming a displayed label never changes a persisted
raw value.

Hippocrates is public. Never commit hospital policy documents, internal cost
schedules, private correspondence, credentials, patient data, or other sensitive
source material. Sensitive evidence stays outside the repository; record only
the deciding authority, date, and a stable non-sensitive locator. The generic
phrase `private evidence reviewed offline` alone is not sufficient provenance.

## Pending implementation decisions

These require review before their feature ships, but do not need invented
institutional facts.

| ID | Decision needed | Current position |
|---|---|---|
| I-005 | Re-verification history representation | Current `[Date]` is adequate for V1 if only timestamp is required; introduce a model only if provenance metadata becomes a real requirement |

## Rejected directions

- a generic `Entry` model;
- free text on `Intervention`;
- CloudKit or any other sync in v1;
- drug-specific dosing, result interpretation, treatment recommendations,
  unversioned clinical reference content, or clinical formulas outside the
  reviewed RXcalc boundary;
- hidden permanent dismissal of stale-answer warnings;
- silent backup merge or store replacement;
- hardcoded cost values or unapproved taxonomy seeds; and
- architecture justified only by a README statement when a compiler/build/test
  control can enforce it.
