# RXcalc implementation plan

## Objective

Add an offline, clinician-facing calculation workspace to Hippocrates with the
transparent evidence and auditability expected from tools such as MDCalc and
GlobalRPH, while preserving Hippocrates' stricter privacy boundary. RXcalc is a
formula tool, not an autonomous prescriber: it computes only from values the
clinician enters, stores no patient inputs or results, and never turns a result
into a drug, dose, threshold interpretation, or treatment recommendation.

Competitor products inform interaction design only. Every equation is
implemented independently from a primary publication or an official clinical or
government source.

## Product and safety contract

- RXcalc remains fully functional in airplane mode and contains no networking,
  third-party package, analytics, account, or EHR integration.
- Inputs and results are ephemeral view state. No RXcalc field is added to
  SwiftData, backup archives, logs, or analytics.
- No patient name, MRN, room, encounter, date of birth, or free-text context is
  requested.
- Every calculator declares a stable identifier, formula version, intended
  population, canonical units, rounding policy, limitations, citations, source
  metadata-check date, and clinical-review status.
- Missing, non-finite, nonpositive, implausible-age, out-of-population,
  conversion-overflow, and output-overflow inputs fail visibly. Values are never
  guessed, rounded up, clamped, or silently substituted.
- Full precision is retained through the calculation. Rounding is a display
  policy and never changes the returned value.
- Results always identify the formula, version, units, and draft-review status.
  The core limitation sits beside the result rather than in a footer alone.
- Drug-specific recommendations, pediatric dosing, time-critical treatment
  directives, narrow-therapeutic-index dosing, and protocol content remain
  outside the current product. Reopening them requires a new owner/doctrine
  decision before clinical or regulatory review begins.
- No clinical-use claim or distribution occurs before device acceptance,
  immutable P-008 clinical approval, P-009 regulatory/claims review, and explicit
  owner authorization for the exact build.

## Architecture

```text
Hippocrates/Features/RXCalc/
  RXCalculatorCatalog.swift       typed catalog, structured units, source metadata
  RXClinicalReviewRegistry.swift stateless Draft-only status and source coverage
  RXCalculations.swift            Foundation-only units, validation, formulas
  RXCalcView.swift                SwiftUI catalog, forms, results, and limitations

HippocratesTests/
  RXCalcTests.swift               vectors, unit parity, boundaries, review registry

HippocratesUITests/
  RXCalcCatalogAccessibilityTests.swift  compact catalog Dynamic Type/text-clipping evidence

docs/clinical-review/rxcalc-r1-v1/
  activation-boundary.json        fail-closed no-activation contract
  bundle-files.txt                exact immutable candidate path set
  bundle.sha256                   CI-enforced worktree content manifest
  claims-and-policy-matrix.md     display claims, units, and review questions
  golden-vectors.json             formula and unit-conversion fixtures
  packet-schema.json              external review-record schema
  reviewer-checklist.md           blank identity and evidence checklist
  reviewer-packet.md              unsigned P-008 evidence map and procedure
  source-provenance.json          source identities and artifact gaps
```

`RXCalculations.swift` is pure and imports Foundation only. It has no SwiftUI,
SwiftData, ledger-model, backup, or configuration dependency. The views depend
on that pure layer. `CaptureHomeView` places RXcalc in the existing post-first-run
tab shell without making any calculator result durable.

The build scanner uses fail-closed naming heuristics plus exact source identities.
It permits the five reviewed division seams only in `RXCalculations.swift`; flags
calculator/equation types outside RXcalc and dose-selection declarations/types;
and rejects `@AppStorage`, `@SceneStorage`, `UserDefaults`, SwiftData, or ledger
coupling inside RXcalc. These controls force review but are not semantic proof.
Networking, external addresses, unreviewed slash syntax, and third-party
packages remain prohibited repository-wide.

## Delivery slices

### R0 — product pivot and executable boundary

- Replace the old permanent “no calculations” contract with the bounded RXcalc
  contract in the README, product vision, architecture, decision register, and
  roadmap.
- Keep dose recommendations and institutional reference content prohibited.
- Add scanner self-tests and hosted planted probes for allowed RXcalc arithmetic,
  stray calculator types, dose-recommendation types, persistence coupling, and
  unreviewed slash syntax.

Exit evidence: clean repository passes the scanner; each planted violation fails
with its dedicated diagnostic.

### R1 — useful stateless MVP

Ship a searchable catalog and these tools:

1. Cockcroft–Gault estimated creatinine clearance for adults with stable renal
   function. The clinician explicitly supplies the calculation weight; RXcalc
   does not choose actual, ideal, or adjusted weight.
2. Race-free 2021 CKD-EPI creatinine eGFR for adults using standardized serum
   creatinine, reported as indexed `mL/min/1.73 m²` without CKD staging or a dose
   interpretation.
3. Body-size metrics for adults age 20 or older: BMI and Mosteller BSA from one
   height and weight entry, without deriving a medication dose.

Metric and US-unit entry convert to one canonical internal representation.
Changing a selected unit clears the affected numeric field rather than silently
reinterpreting it. Displayed results are invalidated whenever any input changes
and require an explicit Calculate action.

Exit evidence: exact source/version metadata; National Kidney Foundation CKD-EPI
golden vectors; equation-derived Cockcroft–Gault, CDC BMI, and Mosteller engineering fixtures;
conventional and SI unit parity; locale-decimal parsing; invalid, implausible-age,
non-finite, and numeric-overflow tests; monotonicity checks where supported;
288 scanner checks; Release build, analyzer, and iOS simulator tests green.

R1 remains draft after the engineering exit. Immutable P-008 clinical review,
real-device acceptance, P-009 regulatory/claims review, and owner-authorized
distribution are separate gates.

### R1.1 — discovery, input ergonomics, and review readiness

Harden the authorized R1 workflow without changing any formula, source,
population, limitation, rounding policy, interpretation, or product claim:

- normalize punctuation, case, diacritics, and whitespace, then require every
  search token to match across titles, categories, populations, equations,
  structured units, limitations, formula IDs, citations, and source locators;
- group the catalog by category;
- keep Draft, summary, and population before inputs while moving long-form
  limitations and evidence below the working area;
- add keyboard dismissal and stable accessibility identifiers to required
  controls and results; and
- add a fail-closed registry with no production activation path plus a
  deterministic P-008 candidate-review packet whose every path is immutable.

The packet stores no reviewer identity or copyrighted source artifact. CI
recomputes `bundle.sha256`, validates the reviewer-schema contract, and plants
candidate drift, a hidden dangling RXcalc source, a hidden packet entry,
malformed/shrunken allowlists, and manifest self-reference. Direct and sandboxed
scanner probes also prove production reviewed-status construction is rejected.
Clinical reviewers later generate a timestamp-free manifest from raw Git blobs
at one full candidate object ID. The packet cannot activate reviewed status;
P-008 still requires a separately accepted, executable continuing-binding design.

### R1.3 — safety verification layer (engineering, Draft-only)

Strengthen testability and reproducibility without changing authorized equation
arithmetic, populations, limitations, claims, or clinical-review activation:

- attach `RXCalculationProvenance` to every successful adult R1 result (inputs,
  normalized units, formula IDs, rounding-policy identity, Draft review status,
  human-review-required, non-recommendation flag, timestamp);
- introduce typed quantities / unit kinds (mass, length, creatinine
  concentration) so incompatible kinds are difficult to combine accidentally;
- extend property-style, table-driven, boundary, and malformed-input tests;
- strengthen de-identification adversarial synthetic fixtures and pure
  acknowledgment-gate tests;
- extend backup corrupt/unsupported-version/partial-restore coverage proving no
  destination mutation on rejection;
- document remaining pharmacist-validation gaps on the reviewer checklist;
- provide `Scripts/linux-pure-safety-driver.swift` for Foundation-only checks on
  non-Xcode hosts.

R1.3 does not activate P-008, does not authorize clinical use, and does not add
R2/R3 dose arithmetic. All formulas remain Draft.

### R1.2 — compact catalog Dynamic Type regression evidence

Add one dedicated, scanner-owned UI-test target without changing formula
arithmetic, sources, populations, limitations, rounding, claims, persistence, or
runtime status. The configured hosted flow:

- creates a fresh iPhone SE (3rd generation), iOS 18.5 simulator, sets and reads
  back Accessibility 5, and completes the real first-run flow;
- navigates through either the direct RXcalc tab or compact More fallback;
- asserts reachable search, exact Draft and non-retention warnings, both category
  headings, and complete semantic title, summary, and Draft status for all three
  rows;
- runs Dynamic Type and clipped-text audits and keeps named screenshots; and
- preserves the exact `.xcresult` for 14 days.

The portable scanner passes 299 checks locally; exact-head hosted Xcode/UI
execution remains pending. This catalog automation does not inspect search
results, exercise detail forms, cover VoiceOver/keyboard behavior or physical
hardware, or provide human visual judgment. It cannot close A8, P-008, or P-009,
answer P-010, or authorize signing or distribution.

R2-R4 are unstarted backlog hypotheses outside the current v1 commitment. Each
requires a fresh owner decision and its stated evidence before implementation.

### R2 — cardiac-safety formulas

Add a manual QTc calculator that reports Bazett, Fridericia, Framingham, and
Hodges side by side. It accepts QT plus heart rate or RR, never reads an ECG,
never chooses a hidden preferred result, and applies no universal risk color or
treatment cutoff.

Exit evidence: primary-source vectors, rate-extreme warnings, formula labels,
and cardiology review.

### R3 — clinician-supplied dose arithmetic

Add dimensional arithmetic for total dose, volume, and pump rate only after
independent usability review. Every drug, ordered dose, concentration, maximum,
and duration comes from a clinician-verified order or current label; RXcalc
provides none of them.

Exit evidence: dimensional compatibility tests, visible conversion trace,
medication-number display rules, and pharmacist review.

### R4 — workflow conveniences

Consider favorites and recent tools after R1 use. Persisting either requires an
explicit product decision and a reviewed SwiftData schema, migration, backup
format, restore, and privacy change. Until then, the catalog remains stateless.

### Outside the current product — not an approved delivery slice

Drug-specific renal recommendations, pharmacokinetics, dilution, compounding,
and reference tables remain prohibited product content. Reconsidering them
requires a new explicit owner/doctrine decision before implementation planning,
followed by current label/guideline provenance, effective-date tracking,
specialty approval, change monitoring, retirement behavior, and regulatory
review. R0-R4 grant no approval for this work.

## Review-packet commands

```sh
Scripts/rxcalc-review-packet.sh --verify
Scripts/rxcalc-review-packet.sh --commit <full-lowercase-object-id> --output /secure/path/candidate.tsv
```

`--verify` is the ordinary source-drift gate. `--commit` reads the exact
allowlisted blobs from Git, rejects missing files, symlinks, unsupported modes,
malformed/unsorted/duplicate allowlists, any extra RXcalc file, and any packet
entry outside the mandatory allowlisted core plus the sole derived
`bundle.sha256` exception, then emits a timestamp-free manifest. Embedding that
digest in a signed reviewer record does not itself activate review status.

## Formula authorities for R1

| Calculator ID | Authority | Version contract |
|---|---|---|
| `cockcroft_gault_1976@1.0.0` | Cockcroft DW, Gault MH. *Nephron*. 1976;16(1):31-41. PMID 1244564. DOI 10.1159/000180580 | Original adult equation; entered calculation weight; published 0.85 female coefficient; stable renal function warning |
| `ckd_epi_creatinine_2021@1.0.0` | Inker LA et al. *N Engl J Med*. 2021;385:1737-1749. PMID 34554658; official NKF/NIDDK implementation guidance | Race-free adult creatinine equation; standardized creatinine; indexed result; whole-number display |
| `body_mass_index_cdc_metric@1.0.0` | Centers for Disease Control and Prevention. BMI Frequently Asked Questions. June 28, 2024 | Metric adult BMI, age 20 or older; no category or treatment interpretation |
| `body_size_mosteller_1987@1.0.0` | Mosteller RD. *N Engl J Med*. 1987;317:1098. PMID 3657876. DOI 10.1056/NEJM198710223171717 | Mosteller BSA only; no dose derivation |

## Completion definition

The broad RXcalc goal is not complete when R1 merely renders. Engineering
completion requires the bounded catalog, authoritative fixtures, unit-safe pure
implementations, adjacent limitations, scanner/probe enforcement, and exact-head
hosted Release build, analyzer, and simulator evidence. R1.2 engineering
verification specifically requires exact-head execution of the selected UI test
and preserved result-bundle evidence; a local scanner pass is insufficient.

Clinical or field eligibility additionally requires accessible one-handed device
acceptance; immutable, version-specific P-008 clinical approval; P-009
regulatory/claims determination; and explicit owner authorization for the exact
distribution build. No later slice or release gate is implied by R1 engineering
completion.

R1 is the first complete vertical slice, not a claim that the whole RXcalc
program or public-release gate is finished.
