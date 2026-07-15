# Architecture

## System shape

Hippocrates is one iOS application target and one unit-test target. Feature
boundaries are directories inside the app target, not separate packages. This
keeps Phase 1 at zero third-party and zero Swift Package dependencies while still
making ownership clear.

```text
Hippocrates/
  App/             composition root and root navigation
  Models/          persisted enum vocabulary
  Persistence/     versioned schemas, migration plan, container factory
  Backup/          value archive, validation, import/export transport
  Safety/          de-identification findings and save/import gates
  Services/        deterministic application operations
  Features/
    Capture/       intervention capture and undo
    Summary/       aggregate views and CSV/print export
    DIVault/       DI form, freshness, search, links, portfolio
    Settings/      editable taxonomies and app configuration
  Export/          CSV, printable documents, and portfolio formatting
  Resources/       privacy manifest and app-owned assets
```

Directories are added only when their feature begins. A protocol or abstraction
must have a real second implementation or a test seam; single-use abstractions are
not architecture.

## Dependency direction

Views may call application services and read SwiftData models through the injected
`ModelContext`. Services may depend on persisted models and pure value helpers.
Pure safety, ranking, freshness, CSV, and backup validation logic must not import
SwiftUI. Persistence and services never import feature views.

```text
SwiftUI views -> application services -> SwiftData models/container
             -> pure value policies -> Foundation value types
```

No layer owns a networking client because no networking layer exists.

## State ownership

### Durable state

The local SwiftData store is the only durable application state. `SchemaV1` is
immutable after release; future changes introduce `SchemaV2` and an explicitly
reviewed migration stage. UUIDs are portable backup identity. SwiftData
`PersistentIdentifier` values never leave their store.

`AppConfig` is a single logical row obtained through one main-actor
fetch-or-create service. The unique sentinel prevents two surviving rows, but
SwiftData uniqueness uses upsert behavior; callers must not insert configuration
ad hoc.

### View state

Capture selections, snackbar visibility, dismissed staleness interstitials, and
multi-step form position are ephemeral SwiftUI state. They are not persisted as
extra model fields. A DI draft is durable once the user first saves it.

After bootstrap, every ordinary launch opens directly into capture. A genuinely
empty installation may instead present the configuration gate needed to make
capture possible. Once guarded restore UI ships, that same pre-bootstrap gate
also offers restore before creating configuration. This first-run gate is an
explicit exception to the launch-directly-into-capture rule, not a dashboard,
welcome flow, or recurring home screen.

### Feedback and failure state

User-correctable failures are visible in the feature that caused them: matched
identifier ranges in the de-identification sheet, validation errors in import,
and a backup/export reminder in the shell. Store-open and migration failures fail
loudly; the app never silently deletes the store or falls back to memory.

## Concurrency and SwiftData rules

- `ModelContainer`, `ModelContext`, and model-mutating services are main-actor
  isolated.
- Persisted `@Model` reference objects are not passed across actors and are never
  marked `@unchecked Sendable`.
- Backup and export DTOs are `Sendable` values. Expensive value-only formatting
  may leave the main actor only after the DTO snapshot is complete.
- The capture screen never owns an unbounded `@Query`. It fetches small active
  taxonomies and a bounded recent-intervention window for ranking.
- `#Predicate` is used only for operations known to compile reliably. DI
  full-text search fetches the small record set and filters lowercased strings in
  memory.

Comments should explain `@Model` reference semantics, inverse relationships,
`@Query` re-evaluation, and `modelContext` lifetime where a first-time Swift
maintainer would otherwise reasonably misread the code.

## Intervention capture transaction

The three selections form an ephemeral `CaptureDraft`. The third tap constructs
and inserts one `Intervention`, using the selected type's configured default cost
value when present. Save occurs immediately with light haptic feedback.

Service line, minutes, and cost override are optional schema values, but their
capture placement is not yet decided. Their eventual controls may add optional
taps but must not add a required tap to type -> class -> acceptance. Until that
interaction is reviewed, the architecture does not assume a default service
line, silently infer minutes, or choose whether cost override occurs before or
after the third-tap save.

The snackbar retains only the inserted UUID and a cancellable five-second task.
Undo looks up that exact intervention and deletes it. A new save cancels and
replaces the previous snackbar task. There is no intervention detail screen and
no narrative editing path.

Frecency is derived, not persisted: rank active types from a bounded recent
window using deterministic frequency and last-used ordering, then use configured
`sortOrder` and label as stable tie-breakers. The ranking policy is pure and unit
tested.

## DI save boundary

DI text is edited in a form value, not written field-by-field to SwiftData. Save
scans `questionText`, `background`, `answerText`, and `searchStrategy` together.
Each finding retains the field, matched range, category, and text needed to
highlight the issue.

The blocking review sheet requires a disposition for every finding:

- **Remove** returns to editing with that match selected; or
- **Not an identifier** records an in-memory acknowledgement for that exact text
  and that save attempt.

Acknowledgements are not a permanent ignore list. Any edit invalidates affected
acknowledgements, and the next save scans again. Backup import must pass the same
gate before any restore mutation; decode and graph validation alone are not a
privacy review.

The four guarded DI fields are not the only strings in the schema. Tags, citation
titles/locators, citation URL text, and editable taxonomy labels can also become
identifier channels if their UI accepts record-specific prose. Their input
constraints and guard behavior require an explicit design decision; they must
not inherit a silent blanket exception merely because they sit outside the four
named DI fields.

## Freshness policy

Freshness is a pure computation from `answeredAt`, `verifiedOn`, `reviewAfter`,
and the current clock. A record with `answeredAt == nil` is a draft and returns a
draft state before any green/amber/red calculation. Freshness is never stored as
a color or status; search rows and detail views consume the same policy result.

Each answered record carries its own review interval:
`reviewAfter - verifiedOn`. Green lasts through `reviewAfter`, amber begins after
it, and red begins after one additional equal per-record interval. Changing the
current app default therefore does not retroactively move an older record's red
boundary. Save/import validation rejects or explicitly surfaces a
`reviewAfter <= verifiedOn` record instead of manufacturing a zero/negative
interval or color.

Re-verification appends a timestamp to `verificationHistory`, updates
`verifiedOn`, and derives a new `reviewAfter` in one transaction. Dismissing an
amber/red interstitial is view-local and lasts only for the current presentation.

## Backup and restore

Backups serialize versioned value records and foreign UUIDs, never `@Model`
instances. Validation precedes mutation and rejects unknown versions, duplicate
IDs, dangling references, invalid configuration keys, and broken verification
history.

V1 never silently merges. The product decision register tracks whether restore is
limited to pre-bootstrap import or may replace a logically pristine configuration
store. Any destructive replacement of a store containing user records requires a
separate explicit confirmation design and review.

SwiftUI's normal file-import path exposes a security-scoped local file `URL`,
while the source scanner deliberately rejects general URL use. Import therefore
requires a narrow, reviewed scanner exception for one local-file adapter. That
adapter must require `isFileURL`, acquire and release security-scoped access,
read the archive into app-owned `Data` immediately, and expose no URL-opening,
remote-scheme, or sharing behavior. General URL use remains forbidden.

There is no reliable public iOS API that proves whether device/iCloud backup is
enabled. Any first-run backup note is consequently informational and
best-effort; it must not say backup is disabled, enabled, or verified when the OS
does not expose that fact. Hippocrates does not add CloudKit or networking to
improve this signal.

## Export architecture

Every export begins with a main-actor snapshot into immutable value records.
Formatting is deterministic:

- CSV columns and ordering are versioned and locale-independent, and records use
  RFC 4180 quoting for commas, quotes, and line breaks;
- text cells beginning with spreadsheet formula markers (`=`, `+`, `-`, or `@`)
  are neutralized on export without changing the stored taxonomy value;
- currency is stored and summed as integer cents;
- printable summaries receive pre-aggregated values and chart series;
- DI portfolio output preserves the standard response section order; and
- full backup preserves all model fields and relationships, not presentation.

`ShareLink` transfers app-owned `Data`/`Transferable` representations. It never
shares a remote `URL`, so the system has no link-preview fetch to perform.

Acceptance rate is not computed until its denominator is approved. Pending,
rejected, accepted, and not-applicable records cannot be silently included or
excluded by an implementation detail. The summary engine receives the approved
policy explicitly and the export labels the resulting denominator.

`ShareLink` does not report that a recipient actually received a file. Therefore
the meaning of `AppConfig.lastExportAt` remains a decision within the full-backup
flow: backup archive generated, share sheet presented, or another observable
event. Summary and DI-portfolio exports must not reset the backup reminder.
Reminder logic must use the same documented meaning and must not describe
presentation as a confirmed backup.

## Enforced privacy boundary

The Xcode build phase is an always-run control. It verifies the reviewed app/test
target topology, source membership, Swift-only compilation, zero package or
framework linkage, the exact script phase, forbidden networking surfaces, and the
persisted `Intervention` property allowlist. The privacy manifest separately
declares no tracking and no collected data.

This is source-verifiable risk reduction, not an iOS network entitlement and not
a HIPAA compliance program. README language must preserve that distinction.

## Test strategy

1. Pure unit tests cover ranking, freshness boundaries, de-identification
   patterns/ranges/dispositions, draft freshness precedence, per-record red
   thresholds, RFC 4180 formatting, formula-injection neutralization, date
   ranges, and backup graph validation.
2. In-memory SwiftData tests cover relationships, delete rules, configuration
   singleton behavior, save/undo transactions, re-verification history, and full
   backup restore/re-export.
3. Source/project contract tests cover no free text in `Intervention`, no network
   surface, zero packages, manifest contents, and schema/migration registration.
4. SwiftUI tests cover the three-tap path, guard interstitials, stale-answer
   interposition, and search badges.
5. Manual device acceptance covers one-handed timing, haptics, airplane mode,
   printable artifacts, and restore on a clean install.
