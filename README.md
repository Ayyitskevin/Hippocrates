# Hippocrates

[![iOS CI](https://github.com/Ayyitskevin/Hippocrates/actions/workflows/ios-ci.yml/badge.svg)](https://github.com/Ayyitskevin/Hippocrates/actions/workflows/ios-ci.yml)

Hippocrates is a personal, offline professional ledger for one hospital clinical
pharmacist. It records interventions she has already made and drug-information
answers she has already completed. It does not calculate, interpret, dose,
recommend, or advise.

Project direction and delivery evidence live in:

- [`docs/product-vision.md`](docs/product-vision.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/decision-register.md`](docs/decision-register.md)
- [`docs/roadmap.md`](docs/roadmap.md)

This repository supersedes the discarded calculator-oriented prototype. No code,
data model, drug exclusion list, or history from that prototype is carried forward.

## Permanent boundaries

- `Intervention` has no patient identifier or free-text field.
- The app contains no clinical calculation or recommendation path.
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

Hippocrates contains no networking code and declares "Data Not Collected." Data
lives in a local SwiftData store on one device. This is verifiable by inspecting
the source and the App Store privacy label. It is not a HIPAA compliance program,
and this app is not a substitute for institutional policy.

> This regex guard is a heuristic aid. It is not a compliance control and it does
> not make output HIPAA-compliant. The compliance controls are (1) the absence of
> identifier properties in the schema and (2) the user's professional judgment.
> Do not represent this guard as more than it is.

The de-identification guard is intentionally not exposed until DI capture ships;
backup import remains an internal service until that same guard protects restore.

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
   and leaves the reopened store empty; and
7. a fail-closed PBX/configuration/scheme parser plus 257 executable checks and
   negative fixtures for source, resource, import, URL/file-loader, document
   ingress, symlink, physical-identity, canonical-path collision,
   target-dependency, local-store, model-lifecycle, SwiftData backing-data/value,
   persisted-schema/backup-shape drift, and historical-decoder drift.

The three persisted properties intentionally represented without their own
same-named backup fields are `DIQuestion.citations` (rebuilt from
`Citation.questionID`), `DIQuestion.linkedInterventions` (rebuilt from
`Intervention.diQuestionID`), and `AppConfig.singletonKey` (reconstructed as the
canonical `"app"` value). Synthesized `Codable` checks the represented archive's
record types during decoding; `BackupService.validate(_:)` separately owns
cross-record graph integrity and domain invariants.

This hardens persistence without inventing product policy. Taxonomy editors,
capture, summary, DI, and restore UI remain gated by the affected product and
implementation decisions listed below.

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
security-scoped, AppConfig-ownership/lifecycle, persisted-schema/backup-shape,
historical-decoder, source, resource, test-loader, and configuration violations,
then proves the sandboxed Xcode phase rejects every declared-input class without
traversing
Xcode's generated `project.xcworkspace`, before running the Xcode 16.4 Release
build, static analysis, and file-backed and in-memory tests on iOS 18.5. Local
scanner self-tests are useful, but they are not substitutes for an exact-head
hosted Apple-platform result.

## Privacy manifest and App Store label

`Hippocrates/Resources/PrivacyInfo.xcprivacy` declares no tracking and no collected
data types. It does not declare a file-timestamp required-reason API because the
current exporter serializes `Data` to `FileWrapper` without reading file metadata.
Add a reason only if shipping code later accesses one of Apple's listed metadata
APIs. Empty tracking-domain and required-reason arrays are omitted as directed by
Apple's TN3181.

The App Store privacy label is not encoded by the manifest. An App Store Connect
Account Holder, Admin, or App Manager must separately publish **Data Not
Collected** before distribution. No TestFlight or App Store action is authorized
by this repository milestone.

## Required decisions before affected features ship

1. Whether hospital policy permits a PHI-free personal work ledger on a personal
   device. This gates use on shift, not foundation development.
2. Whether the institution publishes cost-avoidance values. Stored defaults
   remain `nil`; the schema and backup preserve `nil` separately from zero.
3. Whether the department has an intervention taxonomy; otherwise ASHP categories
   require explicit approval before seeding. Taxonomies remain empty.
4. Whether the default summary range is annual or quarterly.
5. Whether DI staleness defaults to 12 months or 6 months. The stored default
   remains `nil`.
6. Whether the frozen DI requestor, question-class, urgency, and source-tier
   vocabulary matches the intended workflow. DI UI does not ship until confirmed.

Supply and record these answers through the canonical
[D0 response worksheet](docs/decision-register.md#d0-response-worksheet). It
requires a deciding authority, date, and non-sensitive provenance, and it forbids
committing private institutional material to this public repository.

The accepted implementation decisions and remaining gates—including restore
readiness, editable-label identifier risk, metric semantics, local-file import,
and `lastExportAt` meaning—are tracked in
[`docs/decision-register.md`](docs/decision-register.md).

## Primary implementation references

- [Apple: Migrate to SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/)
- [Apple: `VersionedSchema`](https://developer.apple.com/documentation/swiftdata/versionedschema)
- [Apple: `SchemaMigrationPlan`](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [Apple: privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple TN3181: Debugging invalid privacy manifests](https://developer.apple.com/documentation/technotes/tn3181-debugging-invalid-privacy-manifest)
- [Apple: required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Apple: App Store privacy details](https://developer.apple.com/app-store/app-privacy-details/)
