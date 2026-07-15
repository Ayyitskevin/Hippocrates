# Hippocrates

Hippocrates is a personal, offline professional ledger for one hospital clinical
pharmacist. It records interventions she has already made and drug-information
answers she has already completed. It does not calculate, interpret, dose,
recommend, or advise.

This repository supersedes the discarded calculator-oriented prototype. No code,
data model, drug exclusion list, or history from that prototype is carried forward.

## Permanent boundaries

- `Intervention` has no patient identifier or free-text field.
- The app contains no clinical calculation or recommendation path.
- The app contains no networking, server, account, sync, CloudKit, analytics,
  crash-reporting SDK, notification, widget, intent, or third-party package.
- SwiftData is explicitly configured with managed CloudKit sync disabled.
- The app target has an always-run build phase that resolves the actual app/test
  source membership and fails on networking APIs, network-opening UI, Foundation
  URL loading, linked frameworks, hard-coded web addresses, target-topology drift,
  or Swift Package dependencies.

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

## Current milestone

The first milestone is deliberately limited to build-order steps 10.1 and 10.2:

1. one iOS 18 Xcode project with an app target and test target;
2. `SchemaV1`, `HippocratesMigrationPlan`, and explicit local-only
   `ModelContainer` wiring from commit one;
3. a versioned JSON backup format with validated, empty-store restoration; and
4. lossless in-memory round-trip tests for every model and relationship.

Taxonomy seeding, editable configuration, intervention capture, and all later UI
remain gated on the product-owner answers listed under **Required decisions**.

## Build

Requirements: Xcode 16 or newer, Swift 6 language mode, and an iOS 18 simulator.

```sh
xcodebuild -list -project Hippocrates.xcodeproj
xcrun swift Scripts/NetworkBoundaryScanner.swift --self-test
xcodebuild test \
  -project Hippocrates.xcodeproj \
  -scheme Hippocrates \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The current implementation was authored on Linux, where Apple SDKs and
`xcodebuild` are unavailable. The hand-authored project file is provisional until
the commands above pass on macOS; that limitation must not be described as a
successful Apple-platform build.

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

## Required decisions before build-order steps 10.3 and 10.4

1. Whether hospital policy permits a PHI-free personal work ledger on a personal
   device. This gates use on shift, not local development.
2. Whether the institution publishes cost-avoidance values. Values remain empty.
3. Whether the department has an intervention taxonomy; otherwise ASHP categories
   require explicit approval before seeding. Taxonomies remain empty.
4. Whether the default summary range is annual or quarterly.
5. Whether DI staleness defaults to 12 months or 6 months.

Schema review must also confirm the representation of app-wide cost values,
singleton enforcement for `AppConfig`, verification history, empty-only versus
replacement restore, and how editable taxonomy labels are kept from becoming an
indirect identifier channel.

## Primary implementation references

- [Apple: Migrate to SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/)
- [Apple: `VersionedSchema`](https://developer.apple.com/documentation/swiftdata/versionedschema)
- [Apple: `SchemaMigrationPlan`](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [Apple: privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Apple TN3181: Debugging invalid privacy manifests](https://developer.apple.com/documentation/technotes/tn3181-debugging-invalid-privacy-manifest)
- [Apple: required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Apple: App Store privacy details](https://developer.apple.com/app-store/app-privacy-details/)
