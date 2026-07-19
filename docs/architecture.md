# Architecture

## System shape

Hippocrates is one iOS application target, one unit-test target, and one UI-test
target. Feature boundaries are directories inside the app target, not separate
packages. This
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
    RXCalc/        stateless, source-versioned formulas and transient forms
  Export/          CSV, printable documents, and portfolio formatting
  Resources/       privacy manifest and app-owned assets
HippocratesTests/  pure, persistence, integration, and architecture tests
HippocratesUITests/
  RXCalcCatalogAccessibilityTests.swift  compact catalog Dynamic Type evidence
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

RXcalc follows a separate one-way branch: SwiftUI form to pure Foundation
calculation values. That branch cannot import SwiftData or call ledger,
configuration, backup, or persistence services.

## State ownership

### Durable state

The local SwiftData store is the only durable application state. No store schema
has been distributed yet, so `SchemaV1` may still receive pre-release
corrections. After the first distributed build it is immutable; future changes
introduce `SchemaV2` and an explicitly reviewed migration stage. UUIDs are
portable backup identity. SwiftData `PersistentIdentifier` values never leave
their store.

`AppConfig` is a single logical row obtained through one main-actor
fetch-or-create service. The unique sentinel prevents two surviving rows, but
SwiftData uniqueness uses upsert behavior; callers must not insert configuration
ad hoc. Normal creation requires a clean `ModelContext`, saves only its own
insert, and rolls back that insert on failure. Restore uses a separate no-save
entry point inside its already-validated transaction.

`AppConfigService` retains the only instance of a nested `Authority` class whose
initializer is file-private. Every `AppConfig` initializer and its staleness
mutator requires that authority, has no defaulted argument, and checks reference
identity against the canonical instance. Consequently safe contextual
initialization, aliases, metatypes, extensions, and bound mutators outside the
service cannot create or mutate a configuration row. A distinct `Authority`
instance fails the identity check; unsafe-memory spellings are independently
source-forbidden rather than treated as supported runtime behavior.

All model-deletion spellings are closed outside one exact pending-delete test
fixture. Any future shipping deletion path requires a reviewed, service-specific
exception, so configuration cannot be deleted ad hoc.

SwiftData also synthesizes restricted backing-data construction and mutation
seams that do not call the handwritten initializer. The scanner therefore pins
the exact AppConfig initializer/mutator bodies and assignment semantics plus the
reviewed service authority, construction, insert, and mutation seams; it rejects
explicit authority, constructor, mutation, alias, metatype, shadow, extension,
unsafe-memory, direct `PersistentModel.setValue`, and backing-data spellings
across both app and test sources. This is an access-control change only: no
persisted property, schema version, migration, or product default changed.

`AppConfig.stalenessIntervalMonths` is optional: `nil` is the durable safe
state while P-005 is unanswered. A positive value must be explicitly supplied;
the persistence layer contains no six- or twelve-month default.

### View state

Capture selections, snackbar visibility, dismissed staleness interstitials, and
multi-step form position are ephemeral SwiftUI state. RXcalc inputs/results are
view-local: they may remain while the live tab/detail hierarchy exists, but are
discarded when that view is destroyed or the process exits. They never enter
SwiftData or backup DTOs. A DI draft is durable once the user first saves it.

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


## RXcalc calculation boundary

RXcalc is a stateless feature branch beside the durable ledger, not a service on
top of SwiftData. `RXCalculatorCatalog.swift` owns typed descriptors, stable
formula identifiers, source metadata-check dates, limitations, and structured
canonical input/output units. `RXClinicalReviewRegistry.swift` owns the
fail-closed, stateless Draft-only runtime value and exact per-calculator source
coverage. Future reviewed-state wording lives only in the external candidate
packet; shipping code has no alternate status value, production
activation literal or metadata-injection path. `RXCalculations.swift` owns unit
conversion, validation, and pure
formulas; `RXCalcView.swift` owns transient text entry and display.

The R1 catalog contains Cockcroft–Gault creatinine clearance, 2021 CKD-EPI
creatinine eGFR, CDC metric adult BMI for age 20 or older, and Mosteller BSA.
Competitor products influence navigation only; formula code is derived from the
primary publication or official source recorded in the descriptor. BMI and BSA
retain separate source identities even though they share one height/weight form.

Every formula rejects missing, non-finite, nonpositive, implausible-age, and
numeric-overflow inputs. Unit changes clear the affected numeric field so a
retained number cannot silently change meaning. Locale decimal separators are
normalized before parsing. Results retain full precision, round only for display,
repeat draft status and formula identifiers beside the output, and never emit a
dose, CKD stage, BMI category, or treatment interpretation.

All R1 content remains Draft while P-008 is open. The app does not accept a
commit identifier, digest, date, or caller-supplied review record as authority;
every production call to the registry returns Draft. The exact-source helper
requires each calculator's ordered formula identifiers to match its descriptor,
but source completeness alone cannot grant reviewed status. Candidate wording
for a future reviewed state lives only in the external packet so reviewers can
assess it before any separately approved runtime representation or binding
mechanism is designed.

The tracked `bundle.sha256` manifest binds each clinical source, displayed
claim, integration seam, test, scanner/CI control, and governance artifact in the
candidate-review packet. Every listed path is immutable for that candidate. The
verifier closes the review-packet directory to its exact allowlisted core plus
the sole derived `bundle.sha256` exception, and closes RXcalc to its exact four
regular files. Both closures include hidden entries and dangling symlinks. The
verifier requires exactly one TAB per allowlist record and a terminal line feed;
rejects unsafe paths, duplicate or unsorted entries, missing or untracked files,
and unsupported Git modes; and generates a timestamp-free candidate manifest
from raw Git blobs at one exact full Git object ID. CI plants bundled content
drift, malformed allowlists, dangling sources, and extra packet entries and
requires stable rejection diagnostics. Copyrighted source artifacts, reviewer
qualifications, accepted keys, signature verification, cadence, dispositions,
and signed records stay in controlled external evidence.

This packet deliberately does not implement P-008 status activation. Completing,
signing, or hashing it cannot make the app leave Draft. Any future reviewed-status
implementation requires a separately accepted design that verifies the transition
from exact reviewed candidate bytes into production, continuously binds later builds
to the signed immutable candidate, handles expiry and withdrawal, and states
honestly which checks occur in runtime versus CI/release tooling. Until that
design and independent review exist, any bundle change creates a new Draft
candidate rather than preserving an approval.

Device acceptance, P-009 regulatory/claims review, and explicit owner
distribution approval remain separate gates.

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
and inserts one `Intervention`, explicitly copying the selected type's configured
default when present. `InterventionType.defaultCostAvoidanceCents` is the single
configuration source; the intervention retains that optional value as a historical
snapshot. `nil` means unknown/unassigned and is not coerced to explicit zero.
Save occurs immediately with light haptic feedback.

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
`verifiedOn`, and derives a new `reviewAfter` in one transaction. Verification
history is strictly increasing and must end at the current `verifiedOn`;
re-verification and restore reject equal or backward dates. Dismissing an
amber/red interstitial is view-local and lasts only for the current presentation.

## Backup and restore

Backups serialize versioned value records and foreign UUIDs, never `@Model`
instances. The codec reads a minimal version envelope before the payload. Backup
format v2 is current. Format v1 owns private, let-only historical records for its
payload and all seven model representations; it never reuses the mutable current
format's records. Synthesized `Decodable` reads that frozen shape, and migration
maps every field explicitly before any store mutation. Its duplicate app-wide
cost map is folded into the matching type-owned default, and a missing type or
conflicting duplicate fails loudly instead of choosing a source silently.

Backup completeness is a hybrid contract because no single comparison proves
the schema, exporter, archive, and restore path together:

- Apple-platform tests enumerate non-transient stored properties from the live
  SwiftData `SchemaV1` metadata. An explicit no-ignored-field manifest must map
  every property to a value-record field, a foreign UUID, an inverse reference,
  or one reviewed reconstructed constant, with no extra record fields.
- The populated fixture constructs its expected `BackupArchive` independently
  from `BackupService.makeArchive`, so exporter omissions cannot pass by being
  compared only with exporter output.
- Store export orders all six UUID-bearing top-level record arrays by
  `UUID.uuidString` before validation and encoding. A direct reversed-payload
  test proves each array sort independently of SwiftData fetch order, while two
  stores built in opposite insertion and relationship-assignment orders must
  produce equal archives and encoded bytes. The singular optional `appConfig`
  record and record-internal arrays retain their semantic order.
- After restore, tests fetch every destination model and assert each scalar,
  relationship, inverse, and reconstructed value directly. Re-export equality
  remains useful evidence, but it is not the sole restore oracle.
- A separate current-format fixture restores all seven model representations
  into a file-backed store without a caller-side save, releases the container,
  and reopens the same store before requiring exact re-export, all seven model
  counts, both reconstructed DI inverses, and the canonical configuration
  singleton.
- The same complete archive is attempted against a pre-created file-backed test
  store with saving disabled. `ModelContext.willSave` must observe all seven
  pending inserts, then the storage failure must leave no pending changes. The
  failed dedicated context is discarded, and a later writable reopen must remain
  empty.
- A literal development-format-v1 archive populates every historical record
  shape, frozen enum value, forward relationship, and inverse seam. Its expected
  v2 archive is constructed independently before validation, restore, direct
  field assertions, and deterministic re-export.
- The Linux source-shape gate pins the persisted-property surface to this
  reviewed backup-format contract and emits `SchemaV1 persisted-property surface
  changed without backup-format review` when a model field drifts.
- The same gate pins the private format-v1 outer archive, payload, and seven
  records to let-only synthesized decoding and emits `BackupArchive v1 decoder
  changed outside immutable compatibility contract` on any shape, mutability,
  reuse, default, customization, extension, or nested-declaration drift.

The three deliberate non-record representations are
`DIQuestion.citations`, reconstructed from `Citation.questionID`;
`DIQuestion.linkedInterventions`, reconstructed from
`Intervention.diQuestionID`; and `AppConfig.singletonKey`, reconstructed as the
canonical `"app"` constant. They remain explicit entries in the manifest rather
than ignored fields.

Synthesized `Codable` supplies current-format archive record-shape and value-type
decoding; synthesized `Decodable` does the same for the frozen format-v1 records.
Neither proves cross-record references or clinical/domain semantics.
`BackupService.validate(_:)` separately rejects graph defects and domain-invalid
values before restore mutates a store.

The Linux gate also rejects custom `CodingKeys`, decoder initializers, and
encoder methods in `BackupArchive.swift`, keeping the reviewed v2 archive shape
on synthesized `Codable`; its format-v1 contract likewise rejects defaults,
mutable fields, current-format record reuse, custom members, and extensions.

Validation precedes mutation and rejects unknown versions, duplicate IDs,
dangling references, negative cost or intervention-duration values, nonpositive
configured staleness, non-increasing verification history, and review dates that
do not follow verification. A migrated development-format v1 archive must satisfy
these hardened invariants; migration never invents clinical dates. Backup format
evolution is independent of SwiftData schema version evolution.

Restore never silently merges. The product decision register tracks whether it is
limited to pre-bootstrap import or may replace a logically pristine configuration
store. Any destructive replacement of a store containing user records requires a
separate explicit confirmation design and review.

SwiftUI's normal file-import path exposes a security-scoped local file `URL`.
The source scanner rejects general URL use, file-picker and document-browser
surfaces, drop/paste/item-provider and external-activity ingress,
security-scoped/bookmark APIs, coordinated file access, and the reviewed
Foundation URL/path content-reader seams. Import therefore requires a narrow,
reviewed scanner exception for one
local-file adapter. That adapter must require `isFileURL`, acquire and release
security-scoped access, read the archive into app-owned `Data` immediately, and
expose no URL-opening, remote-scheme, or sharing behavior. General URL use
remains forbidden. `BackupDocument` can decode supplied bytes but remains
unwired to user-facing import UI until that adapter and the de-identification
restore gate are reviewed together.

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

The Xcode build phase is an always-run control with an exact sandbox input
inventory covering every directory it enumerates and every file it reads. A new
source or control file therefore fails closed until it is declared deliberately;
hosted CI also runs the scanner directly, before Xcode creates its generated
`project.xcworkspace`, so recursive orphan and whole-project-bundle checks
receive specific diagnostics outside Xcode's non-recursive input sandbox. The
sandboxed build phase revalidates every declared project, scheme, source, test,
and resource control without traversing that generated workspace. The scanner's
linear OpenStep-property parser rejects duplicate, missing, nested-string-spoofed,
or malformed required properties. It then binds the exact app/unit-test/UI-test
identities, distinct dependencies through which both test targets depend directly
and only on the app, phase order, eight Debug/Release build configurations with
allowlisted values, and one exact shared-scheme XML execution tree.
Frameworks, packages, compiler injection, detached configurations, shadow user
schemes, symbolic links anywhere beneath the Xcode project bundle, and altered
action settings fail.
The physical topology is also closed:

- recursive regular Swift files beneath Hippocrates/ equal app-target Sources;
- recursive regular Swift files beneath HippocratesTests/ equal unit-test Sources;
- recursive regular Swift files beneath HippocratesUITests/ equal UI-test Sources;
- no target pair duplicates a build ID, lexical path, symlink-resolved path, or
  device/inode identity;
- every source stays lexically and canonically beneath its reviewed root;
- the project file and scanner script are regular files that resolve inside the
  repository;
- PrivacyInfo.xcprivacy is the sole app resource while both test-resource
  phases stay empty;
  a scanner-owned XML property-list contract permits exactly one declaration
  each for Boolean `false` tracking and an empty collected-data array, with no
  additional keys.

Canonical source privileges are keyed only by exact normalized
repository-relative paths. A matching basename or path suffix grants no
store, schema, interpolation, URL, citation, typealias, or extension exception.


RXcalc is the sole reviewed clinical-arithmetic exception. Exact source identity
permits the five audited division seams only in `RXCalculations.swift`. The
scanner uses fail-closed naming heuristics to flag calculator/equation types
outside `Features/RXCalc` and dose-selection types/declarations anywhere. Inside
RXcalc it rejects `@AppStorage`, `@SceneStorage`, `UserDefaults`, SwiftData,
ledger models, configuration, schema, and backup coupling. These controls force
review rather than proving semantics; direct and sandboxed CI probes plant each
diagnostic category.

Shipping imports are allowlisted to the five frameworks the current foundation
uses. `SchemaContractTests` may use Foundation `URL` only in three exact
`storeLocation` declaration/call seams for its file-backed SwiftData fixture;
`BackupRoundTripTests` contains one reserved `https://example.invalid/` citation
literal and one exact pending-delete fixture. `PrivacyManifestTests` alone owns
one exact bundled-byte read. The scanner rejects Foundation URL
tokens; `contentsOf` URL/file initializers; contextual URL initializers;
URL/path streams; FileHandle,
FileWrapper, keyed-unarchive, FileManager content/enumeration seams;
file-picker/document-browser and drop/paste/item-provider surfaces;
security-scoped/bookmark APIs; coordinated file access; external-opening UI;
AppConfig authority/construction/mutation drift; unreviewed model deletion;
transport imports; and external address literals. Low-level socket and
host-lookup APIs, iCloud/ubiquity surfaces,
rich-text links, dynamic invocation and unsafe memory, conditional compilation, bare
slashes, backticked identifiers, and Unicode escapes are closed source surfaces.
Executable string interpolation is an exact per-file expression allowlist.

The shipping store and the one file-backed test store are exact local-only
construction seams with managed CloudKit explicitly disabled. Structural
inspection of the persisted Intervention allowlist masks comments, string
contents, and regex contents before matching braces, so literals cannot hide
later properties. The same Linux control structurally checks the full
`SchemaV1` persisted-property surface against the reviewed backup-completeness
contract, while Apple-platform schema metadata independently checks the runtime
surface. The portable scanner parses the privacy manifest independently of
XCTest, requires XML with exactly one declaration per allowed key, and requires
exactly no tracking and no collected data. The bundled-resource test repeats
that key-cardinality and typed-value contract against the manifest copied into
the app.

This is source-verifiable risk reduction, not an iOS network entitlement and not
a HIPAA compliance program. README language must preserve that distinction.

## Test strategy

1. Pure unit tests cover ranking, freshness boundaries, de-identification
   patterns/ranges/dispositions, draft freshness precedence, per-record red
   thresholds, RFC 4180 formatting, formula-injection neutralization, date
   ranges, and backup graph validation.
2. SwiftData tests use in-memory fixtures for relationships, delete rules,
   configuration singleton behavior, save/undo transactions, re-verification
   history, runtime schema-to-backup coverage, exporter-independent current and
   literal-v1 archive expectations, and direct full-field restore assertions plus
   re-export. File-backed fixtures cover core close/reopen persistence and a
   complete backup restore across container teardown without a caller-side save.
   The same fixture also forces a save-boundary failure, requires rollback to
   clear pending work, discards the failed context, and reopens an empty store.
   Canonical export fixtures invert store insertion and relationship-assignment
   order, reverse all six UUID-bearing payload arrays, and require equal archives
   and encoded bytes.
3. Portable scanner self-tests cover privacy property-list semantics and
   repository integration, plus exact RXcalc identities, formula-division seams,
   persisted-state isolation, and calculation/equation and dose-selection naming
   heuristics. Source/project contract tests cover no free text in Intervention,
   no network surface, zero packages, schema/migration registration, and exact
   app/unit/UI source inventory.
4. Pure RXcalc tests cover authoritative formula vectors, structured units,
   normalized multi-token metadata/evidence search, fail-closed review-registry
   validation, unit equivalence, locale-decimal parsing, population/error bounds,
   numeric overflow, and supported monotonicity properties. The deterministic
   review-bundle script and planted CI probes cover candidate drift, exact parser
   and directory closure, and the permanent-Draft production seam.
5. A dedicated RXcalc UI-test target drives fresh onboarding and compact-tab
   navigation on an iPhone SE (3rd generation) simulator at pipeline-set and
   read-back Accessibility 5; asserts search reachability, complete Draft
   warnings, category headings, and complete row semantics; runs Dynamic Type
   and clipped-text audits; and keeps screenshots in the result bundle. It does
   not cover search-result behavior, detail screens, VoiceOver order, keyboard
   dismissal, physical-device interaction, or human visual judgment, so A8
   remains open.
6. Manual device acceptance covers one-handed timing, haptics, airplane mode,
   printable artifacts, clean-store restore, locale-aware decimal entry,
   input/result invalidation, unit-change input clearing, relaunch non-retention,
   and adjacent RXcalc review/limitation notices.
