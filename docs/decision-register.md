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
| A-006 | DI freshness is computed per record, while verification history is durable | Draft overrides color; red uses a second `reviewAfter - verifiedOn` interval; re-verification never erases history |
| A-007 | DI search filters in memory | The expected data volume is small and this avoids fragile SwiftData string predicates |
| A-008 | GitHub macOS CI validates Xcode 16.4 and iOS 18.5 | Linux development cannot be mistaken for Apple-platform verification |
| A-009 | TestFlight/App Store submission is a human action | Autonomous development does not imply autonomous distribution |
| A-010 | CSV output follows RFC 4180 and neutralizes spreadsheet formula cells | Manager exports remain portable without letting editable labels become executable spreadsheet input |
| A-011 | iOS backup-state messaging is explicitly best-effort | No public API reliably proves device/iCloud backup state, so the app never claims it verified enabled/disabled status |

## Pending product decisions — required before configuration/capture

| ID | Owner | Question | Safe state until answered |
|---|---|---|---|
| P-001 | Jenn / institution | Does hospital policy permit this PHI-free personal work ledger on a personal device? | Build may continue; shift use is prohibited |
| P-002 | Jenn / institution | Are official cost-avoidance values assigned per intervention type? | All values remain empty/configurable |
| P-003 | Jenn | Does the department have an intervention taxonomy, or should an explicitly approved ASHP-derived set be used? | Taxonomies remain empty |
| P-004 | Jenn | Is the default review/export cadence annual or quarterly? | No default summary range is shipped |
| P-005 | Jenn | Is DI staleness 12 months or 6 months? | Schema can store the interval; UI behavior does not ship |

## Pending implementation decisions

These require review before their feature ships, but do not need invented
institutional facts.

| ID | Decision needed | Current position |
|---|---|---|
| I-001 | One source of truth for cost values | Prefer `InterventionType.defaultCostAvoidanceCents`; remove or narrowly define any duplicate app-wide map before V1 data exists |
| I-002 | `AppConfig` singleton lifecycle | One main-actor fetch-or-create service; never rely on a uniqueness exception |
| I-003 | Restore into a bootstrapped clean install | Permit only pre-bootstrap or logically pristine stores unless a separately reviewed destructive replacement flow is approved |
| I-004 | Editable taxonomy labels as an indirect identifier channel | Do not permit per-intervention category creation; approve purpose-specific constraints or guard behavior before the taxonomy editor ships |
| I-005 | Re-verification history representation | Current `[Date]` is adequate for V1 if only timestamp is required; introduce a model only if provenance metadata becomes a real requirement |
| I-006 | Backup format compatibility policy | Decode every supported format explicitly; migration occurs in value space before store mutation |
| I-007 | Acceptance-rate denominator | Do not ship the metric until accepted, rejected, pending, and not-applicable treatment is explicitly approved and labeled |
| I-008 | Optional service-line, minutes, and cost-override capture UX | Preserve type -> class -> acceptance as the only required taps; do not assume placement or defaults before review |
| I-009 | De-identification treatment of tags, citation metadata, and other editable strings | Treat them as possible identifier channels; decide purpose-specific constraints or guard behavior before their editors ship |
| I-010 | Local-file URL boundary for restore | Permit one reviewed security-scoped file adapter only; require `isFileURL`, immediate `Data` capture, and no remote/open/share behavior |
| I-011 | Meaning of `lastExportAt` | Choose an observable event in the full-backup flow; summary/portfolio exports never update it, and generation/presentation is never called confirmed delivery |

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
