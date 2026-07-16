# Decision register

This register separates product facts that only Jenn/Kevin can decide from
implementation decisions the repository owner can make. Pending product facts
are never filled with plausible defaults and never silently converted into
requirements.

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

## Accepted product decisions

No product decision is accepted yet. A P-ID enters this table only after the
named owner or institutional authority reviews an explicit answer. Accepted rows
use the following canonical schema:

| ID | Decision | Deciding authority role | Decision date | Non-sensitive provenance | Implementation consequence |
|---|---|---|---|---|---|

## Accepted implementation decisions

| ID | Resolution |
|---|---|
| I-001 | `InterventionType.defaultCostAvoidanceCents` is the single configurable source; each intervention stores an optional historical snapshot |
| I-002 | One main-actor `AppConfigService` owns lookup, clean-context creation, validation, transactional restore insertion, and the canonical identity-checked authority required for model construction and mutation; unreviewed model deletion remains closed at the source boundary |
| I-006 | Decode each supported backup version explicitly and migrate value DTOs before store mutation |

## Pending product decisions — required before affected features

| ID | Owner | Question | Safe state until answered |
|---|---|---|---|
| P-001 | Jenn / institution | Does hospital policy permit this PHI-free personal work ledger on a personal device? | Build may continue; shift use is prohibited |
| P-002 | Jenn / institution | Are official cost-avoidance values assigned per intervention type? | Type defaults and captured costs remain `nil` unless explicitly supplied; zero never substitutes for unknown |
| P-003 | Jenn | Does the department have an intervention taxonomy, or should an explicitly approved ASHP-derived set be used? | Taxonomies remain empty |
| P-004 | Jenn | Is the default review/export cadence annual or quarterly? | No default summary range is shipped |
| P-005 | Jenn | Is DI staleness 12 months or 6 months? | `AppConfig.stalenessIntervalMonths` remains `nil`; freshness-default UI does not ship |
| P-006 | Jenn | Do the frozen DI requestor, question-class, urgency, and source-tier values match the intended workflow? | No DI UI or distributed schema containing this vocabulary ships |

### D0 response worksheet

Use this worksheet to collect P-001 through P-006 without turning a plausible
default or an informal comment into product policy. For each P-ID, provide:

- **Disposition:** select one listed answer, request an exact change, or defer.
- **Answer:** the selected option or the precise replacement requested.
- **Deciding authority:** role or approving body, without private contact details.
- **Decision date:** an ISO `YYYY-MM-DD` date.
- **Non-sensitive provenance:** a public citation, repository commit/handoff, or
  stable owner-held locator such as `offline-review:<id>`.
- **Affected IDs and follow-up:** any still-open P/I dependencies.

| ID | Answer requested | Required authority/provenance |
|---|---|---|
| P-001 | `permitted`, `not permitted`, or `defer` | Name the deciding institutional role/body and record only a non-sensitive or opaque offline reference |
| P-002 | `official values exist` with an owner-supplied list reference, `no official values`, or `defer` | Name the institutional authority; do not infer values or copy an unapproved/private schedule into the repository |
| P-003 | `department taxonomy supplied`, an explicitly named alternative submitted for approval, or `defer` | Jenn approves the exact referenced list; this repository preapproves no ASHP-derived taxonomy |
| P-004 | `annual`, `quarterly`, or `defer` | Jenn's dated response is sufficient provenance |
| P-005 | `12 months`, `6 months`, or `defer` | Jenn's dated response is sufficient provenance |
| P-006 | approve the listed raw vocabulary unchanged, request exact raw-value changes, or `defer` | Jenn reviews all four groups below; partial approval leaves P-006 pending |

P-006 currently asks Jenn to review these persisted raw values:

- requestor role: `resident`, `nurse`, `attending`, `pharmacist`,
  `student`, `careTeam`, `other`;
- DI question class: `dosing`, `adverseEffect`, `interaction`,
  `compatibility`, `availability`, `administration`,
  `pregnancyLactation`, `therapeutics`, `toxicology`,
  `pharmacokinetics`, `other`;
- urgency: `routine`, `sameDay`, `stat`; and
- source tier: `tertiary`, `secondary`, `primary`, `guideline`, `label`,
  `institutionPolicy`.

Hippocrates is public. Never commit hospital policy documents, internal cost
schedules, private correspondence, credentials, patient data, or other sensitive
source material. Sensitive evidence stays outside the repository; record only
the deciding authority, date, and a stable non-sensitive locator. The generic
phrase `private evidence reviewed offline` alone is not sufficient provenance.

A completed worksheet is still advisory until human review. Once accepted, add
one row to **Accepted product decisions**, remove that P-ID from the pending
table, and update D0 plus the affected milestone. Missing authority, date,
provenance, or a partial answer leaves the existing safe state in force.

## Pending implementation decisions

These require review before their feature ships, but do not need invented
institutional facts.

| ID | Decision needed | Current position |
|---|---|---|
| I-003 | Restore into a bootstrapped clean install | Permit only pre-bootstrap or logically pristine stores unless a separately reviewed destructive replacement flow is approved |
| I-004 | Editable taxonomy labels as an indirect identifier channel | Do not permit per-intervention category creation; approve purpose-specific constraints or guard behavior before the taxonomy editor ships |
| I-005 | Re-verification history representation | Current `[Date]` is adequate for V1 if only timestamp is required; introduce a model only if provenance metadata becomes a real requirement |
| I-007 | Acceptance-rate denominator | Do not ship the metric until accepted, rejected, pending, and not-applicable treatment is explicitly approved and labeled |
| I-008 | Optional service-line, minutes, and cost-override capture UX | Preserve type -> class -> acceptance as the only required taps; do not assume placement or defaults before review |
| I-009 | De-identification treatment of tags, citation metadata, and other editable strings | Treat them as possible identifier channels; decide purpose-specific constraints or guard behavior before their editors ship |
| I-010 | Local-file URL boundary for restore | Permit one reviewed security-scoped file adapter only; require `isFileURL`, immediate `Data` capture, and no remote/open/share behavior |
| I-011 | Meaning of `lastExportAt` | Choose an observable event in the full-backup flow; summary/portfolio exports never update it, and generation/presentation is never called confirmed delivery |
| I-012 | Bootstrap readiness predicate | Define the exact minimum configuration that permits capture and distinguish never-configured, intentionally-empty, and restored states before first-run UI ships |

## Rejected directions

- a generic `Entry` model;
- free text on `Intervention`;
- CloudKit or any other sync in v1;
- clinical calculation/recommendation/reference content;
- hidden permanent dismissal of stale-answer warnings;
- silent backup merge or store replacement;
- hardcoded cost values or unapproved taxonomy seeds; and
- architecture justified only by a README statement when a compiler/build/test
  control can enforce it.
