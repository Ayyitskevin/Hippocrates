# Hippocrates

[![iOS CI](https://github.com/Ayyitskevin/Hippocrates/actions/workflows/ios-ci.yml/badge.svg)](https://github.com/Ayyitskevin/Hippocrates/actions/workflows/ios-ci.yml)

Hippocrates is a free, offline professional workspace for hospital
clinical pharmacists. It records interventions and completed drug-information
work, and includes draft, source-versioned, stateless RXcalc equations. RXcalc
does not choose inputs or doses, interpret results, recommend, diagnose, or
advise.

Project direction and delivery evidence live in:

- [`docs/product-vision.md`](docs/product-vision.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/decision-register.md`](docs/decision-register.md)
- [`docs/roadmap.md`](docs/roadmap.md)
- [RXcalc implementation plan](docs/rxcalc-plan.md)

RXcalc is a clean, governed rebuild, not a revival of the discarded
calculator-oriented prototype. No prototype code, data model, drug exclusion
list, or history is carried forward.

## Permanent boundaries

- `Intervention` has no patient identifier or free-text field.
- Clinical arithmetic is allowed only inside the reviewed, stateless RXcalc
  boundary; dose selection, result interpretation, treatment recommendations,
  and institutional protocol/reference content remain prohibited.
- The app contains no networking, server, account, sync, CloudKit, analytics,
  crash-reporting SDK, notification, widget, intent, or third-party package.
- SwiftData is explicitly configured with managed CloudKit sync disabled.
- The app target has an always-run, sandboxed build phase with every reviewed
  directory and file declared explicitly. It inventories regular app/test Swift
  files and app resources, proves exact equality with the canonical PBX
  source/resource phases, and fails on duplicate or escaped paths, networking
  APIs, network-opening UI, unreviewed imports, Foundation URL loading,
  file-picker/document-browser and external drop/paste/item-provider surfaces,
  security-scoped or reviewed path-content access, AppConfig ownership or
  unreviewed model-deletion drift, persisted-schema changes without backup-format
  review, historical backup-decoder drift, iCloud surfaces, compiler injection,
  linked frameworks, external
  address literals, altered build configurations or schemes, project-bundle
  symlinks, physical-file aliases, or package dependencies.

Hippocrates contains no networking code and the repository is designed to
support an App Store **Data Not Collected** label. The actual privacy answer must
be verified against the exact release build and published separately by the
owner. Ledger data lives in a local SwiftData store on one device; RXcalc inputs
and results are transient. This is not a HIPAA compliance program or a substitute
for institutional policy.

> This regex guard is a heuristic aid. It is not a compliance control and it does
> not make output HIPAA-compliant. The compliance controls are (1) the absence of
> identifier properties in the schema and (2) the user's professional judgment.
> Do not represent this guard as more than it is.


## Current foundation

The pre-release foundation now contains:

1. one iOS 18 Xcode project with an app target and test target;
2. `SchemaV1`, `HippocratesMigrationPlan`, and explicit local-only
   `ModelContainer` wiring from commit one;
3. one main-actor `AppConfigService` whose file-private authority owns
   configuration construction and mutation, while unreviewed model deletion is
   source-forbidden and normal creation is allowed only from a clean context;
4. one type-owned cost-default source, with unknown cost kept distinct from an
   explicit zero-dollar value;
5. backup format v2, a private format-owned, let-only format-v1 decoder with
   explicit full-field value-space migration and validated empty-store
   restoration;
6. hybrid backup-completeness coverage that reconciles live SwiftData metadata
   with an explicit no-ignored-field representation manifest, compares export
   against an independently constructed archive, and asserts every restored
   field directly; plus file-backed close/reopen coverage for the core store
   seams and a complete current-format restore without a caller-side save,
   including exact re-export, both DI inverses, and canonical configuration
   reconstruction, plus a forced save-boundary failure that clears pending work
   and leaves the reopened store empty;
7. a fail-closed PBX/configuration/scheme parser plus 288 executable checks and
   negative fixtures for source, resource, import, URL/file-loader, document
   ingress, symlink, physical identity, canonical-path collision, target
   dependency, local store, model lifecycle, SwiftData backing data/value,
   persisted-schema/backup-shape drift, historical-decoder drift, RXcalc
   placement/persisted-state/arithmetic boundaries, calculation/equation and
   dose-selection naming heuristics, and exact privacy-manifest semantics; and
8. a searchable, stateless draft RXcalc catalog with Cockcroft–Gault,
   2021 CKD-EPI creatinine eGFR, BMI, and Mosteller BSA, backed by versioned
   source metadata, official golden vectors, unit-parity tests, and visible
   limitations.

The three persisted properties intentionally represented without their own
same-named backup fields are `DIQuestion.citations` (rebuilt from
`Citation.questionID`), `DIQuestion.linkedInterventions` (rebuilt from
`Intervention.diQuestionID`), and `AppConfig.singletonKey` (reconstructed as the
canonical `"app"` value). Synthesized `Codable` checks the represented archive's
record types during decoding; `BackupService.validate(_:)` separately owns
cross-record graph integrity and domain invariants.

The ledger and DI v1 surfaces through backup/restore are implemented. RXcalc R1
is the first draft stateless calculation slice. Its base engineering exit passed
at exact commit `1381c6ed8faae824658066855c9635ab2fd917c6` in
[hosted run 29694386275](https://github.com/Ayyitskevin/Hippocrates/actions/runs/29694386275).
R1.1 adds structured units, evidence-aware discovery, input ergonomics, and a
deterministic unsigned clinical-review packet without changing formula
arithmetic. The packet supports Draft candidate review only; it exposes no
production status-activation path. Real-device acceptance, P-008 clinical review,
a regulatory/claims determination, and owner-authorized distribution remain
distinct gates; none is
implied by engineering evidence.

## Build

Requirements: Xcode 16 or newer, Swift 6 language mode, and an iOS 18 simulator.

```sh
xcodebuild -list -project Hippocrates.xcodeproj
/usr/bin/xcrun swift Scripts/NetworkBoundaryScanner.swift --self-test
xcodebuild test \
  -project Hippocrates.xcodeproj \
  -scheme Hippocrates \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The GitHub workflow runs the source boundary directly before Xcode mutates its
project bundle, producing recursive orphan and shadow-scheme diagnostics. It
plants network, inferred file-ingress, external-drop, path/stream-loader,
security-scoped, AppConfig-ownership/lifecycle, RXcalc placement, persisted-state,
arithmetic-seam, calculation/equation, and dose-selection violations, plus
persisted-schema/backup-shape, historical-decoder, source, resource, test-loader,
privacy-manifest, and configuration violations,
then proves the sandboxed Xcode phase rejects every declared-input class without
traversing
Xcode's generated `project.xcworkspace`, before running the Xcode 16.4 Release
build, static analysis, and file-backed and in-memory tests on iOS 18.5. Local
scanner self-tests are useful, but they are not substitutes for an exact-head
hosted Apple-platform result.

## Privacy manifest and App Store label

`Hippocrates/Resources/PrivacyInfo.xcprivacy` declares no tracking and no collected
data types. The boundary scanner requires XML, exactly one declaration for each
of the two allowed keys, Boolean `false` tracking, and an empty collected-data
array; both direct and sandboxed hosted probes plant and require rejection of
tracking drift. It does not declare a file-timestamp required-reason API
because the current exporter serializes `Data` to `FileWrapper` without reading file metadata.
Add a reason only if shipping code later accesses one of Apple's listed metadata
APIs. Empty tracking-domain and required-reason arrays are omitted as directed by
Apple's TN3181.

The App Store privacy label is not encoded by the manifest. An App Store Connect
Account Holder, Admin, or App Manager must separately publish **Data Not
Collected** before distribution. No TestFlight or App Store action is authorized
by this repository milestone.

## Product decisions and remaining gates

The 2026-07-18 owner pivot re-scoped Hippocrates from a single-user tool to a
free, general-audience app for hospital pharmacists. The former
institution-gated product decisions P-001 through P-006 are accepted as
user-owned choices — a first-run responsibility notice, an explicitly offered
and skippable starter taxonomy, user-entered cost defaults, a visible summary
range, a user-selected staleness interval, and the frozen DI vocabulary — and
are recorded with deciding authority, date, and provenance in
[`docs/decision-register.md`](docs/decision-register.md).

P-007 records the owner-directed RXcalc pivot. P-008 remains open. Every formula
stays visibly Draft even if reviewers complete the immutable candidate record;
reviewed status requires a separately accepted activation and continuing-binding
design that this app does not implement. Device acceptance, a regulatory/claims
determination, and every TestFlight or App Store action are separate
owner/external gates.

The active sequence and evidence ledger are [`docs/roadmap.md`](docs/roadmap.md)
and [`docs/rxcalc-plan.md`](docs/rxcalc-plan.md). The dated
[`docs/opus-execution-plan.md`](docs/opus-execution-plan.md) and
[`docs/pharmacist-review.md`](docs/pharmacist-review.md) are historical ledger/DI
snapshots, not current RXcalc approval.

## Primary implementation references

- [Apple: Migrate to SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/)
- [Apple: `VersionedSchema`](https://developer.apple.com/documentation/swiftdata/versionedschema)
- [Apple: `SchemaMigrationPlan`](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [Apple: privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple TN3181: Debugging invalid privacy manifests](https://developer.apple.com/documentation/technotes/tn3181-debugging-invalid-privacy-manifest)
- [Apple: required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Apple: App Store privacy details](https://developer.apple.com/app-store/app-privacy-details/)
