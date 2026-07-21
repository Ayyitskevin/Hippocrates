# RXcalc R1 independent reviewer checklist

This is a blank checklist. Do not commit reviewer identities, private
credentials, signatures, internal policies, or restricted source artifacts to
this public repository.

## Candidate identity

- Full lowercase candidate Git object ID: pending
- Candidate root-manifest SHA-256: pending
- Exact-head hosted CI run URL and head object ID: pending
- RXcalc Accessibility 5 result-bundle artifact locator/digest: pending
- Human screenshot-review record: pending
- External evidence-manifest SHA-256: pending

Generate the Git-object manifest from a detached checkout of the candidate:

~~~sh
Scripts/rxcalc-review-packet.sh \\
  --commit <full-lowercase-object-id> \\
  --output /secure/path/candidate.tsv
shasum -a 256 /secure/path/candidate.tsv
~~~

Two consecutive generations must be byte-identical.

## Required review coverage

- Renal clinical reviewer: Cockcroft–Gault and 2021 CKD-EPI.
- Clinical/pharmacy reviewer: adult BMI and Mosteller BSA.
- Independent computational/release verifier: all formulas, conversions,
  fixtures, display rounding, candidate identity, and evidence manifest.
- P-009 regulatory/claims reviewer: separate record and decision.

The independent computational/release verifier also inspects the exact-head
R1.2 `.xcresult`: confirm the selected UI test ran on the iPhone SE (3rd
generation), iOS 18.5 simulator at pipeline-verified Accessibility 5 and that its
semantic assertions and Dynamic Type/text-clipping audits passed. Then separately
inspect every kept screenshot for visual clipping or overlap and record the
result. This supplemental evidence does not replace detail-screen, VoiceOver,
keyboard, or physical-device A8.

For every covered formula, inspect the lawful external source artifact and its
digest, constants, branches, input/output units, population bounds, rounding,
limitations, displayed copy, golden vectors, unit parity, invalid-input
behavior, and result-adjacent warnings.

Resolve every provenance gap in `source-provenance.json`. A disposition of
`approved` requires zero open findings, explicit cadence, a next-review date,
and event-triggered review conditions. No cadence is supplied by engineering.

## Signed record

Each reviewer record must validate against `packet-schema.json` and use only
`approved`, `changes_required`, `not_approved`, or `withdrawn`. A complete
review set contains exactly one current record for each of the three required
roles, all sharing one review-set ID, candidate commit, root-manifest digest,
and external evidence-manifest digest.

Before signing, independently verify both manifest digests, the candidate
commit as the repository's full resolved object ID, required role/formula
coverage, and a next-review date later than completion and consistent with the
stated cadence. Finalize the JSON, including its predeclared signature locator
and payload marker, then detached-sign the exact file bytes with one method
allowed by the schema. Keep signature bytes external at that locator; signing
the raw record binds every field without JSON canonicalization or self-reference.

Schema validation is necessary but never sufficient. A trusted external process
must verify the signature against an out-of-band accepted key and confirm
qualifications, identity, independence, evidence rights, chronology, and the
complete three-role set before treating any record as P-008 evidence. Keep all
records and qualification evidence in the controlled external location.

## Activation boundary — not implemented

This candidate packet cannot activate reviewed status. Do not edit
`RXClinicalReviewRegistry.swift` to insert review metadata: the app has no
production activation seam, and every packet path is immutable.

Before a future reviewed-status transition can be implemented, a separately
accepted design must provide at least:

1. trusted validation of complete reviewer signatures and formula coverage;
2. executable reviewed-candidate-to-production topology, diff, and exact
   reviewed-byte checks;
3. continuing CI/release verification that rejects later immutable drift;
4. a precise runtime-versus-CI trust boundary rather than claiming the installed
   app can inspect Git source;
5. explicit review-date, expiry, withdrawal, and event-trigger behavior;
6. exact-head scanner, Release build, analyzer, simulator, and device evidence;
7. separate P-009, device, signing, and distribution authorization.

Implementing that mechanism changes this immutable candidate and therefore
requires a new Draft candidate review. Completing this checklist alone never
changes the catalog from Draft.

## Engineering safety-verification notes (not clinical approval)

These items are software-integrity aids for the computational/release verifier.
They do **not** satisfy P-008, do not authorize clinical use, and do not close
any open provenance gap in `source-provenance.json`.

- Every successful adult R1 result exposes `RXCalculationProvenance`: original
  and normalized input traces, formula version identifier(s), rounding-policy
  identity, Draft source-review status title, human-review-required = true,
  is-autonomous-clinical-recommendation = false, and `calculatedAt`.
- Typed quantities (`RXQuantity` + unit kinds mass / length / creatinine
  concentration) make cross-kind combination a compile-time error; runtime
  `RXDimensionalAnalysis.requireKind` documents the boundary.
- Full precision is retained through arithmetic; rounding-policy identities are
  display-only and must not alter returned Doubles.
- De-identification adversarial synthetic fixtures (spaced/labeled MRNs, phone
  variants, room/bed, age-over-89 forms including `y.o.` and "age over N") and
  the unacknowledged-finding save/import gate remain fail-closed; fixtures must
  never contain real patient data.
- Backup codec/restore coverage includes clean round-trip, truncated/corrupt
  payloads, unsupported format versions, and non-empty/pending destination
  refusal without destination mutation.
- Linux pure-function driver: `Scripts/linux-pure-safety-driver.swift` (compile
  with shipped `RXCalculations.swift` + `DeidentificationScanner.swift`).

### Authority gaps still requiring pharmacist / clinical validation

All formulas remain **Draft** pending P-008. Do not treat engineering green as
authority. Explicit open gaps (see also `source-provenance.json`):

| Formula ID | Missing authority / open gap |
|---|---|
| `cockcroft_gault_1976@1.0.0` | Lawful full-text artifact; review of age-range extrapolation beyond original cohort; weight-selection is clinician-owned (app does not choose IBW/AdjBW). |
| `ckd_epi_creatinine_2021@1.0.0` | Independent clinical review; dated NIDDK/NKF snapshot digests; confirmation of all transcribed NKF vectors. |
| `body_mass_index_cdc_metric@1.0.0` | Exact SI conversion vs CDC rounded US customary expression. |
| `body_size_mosteller_1987@1.0.0` | Lawful full-text or equivalent authoritative formula artifact (PubMed record alone is insufficient). |

Out of scope for this candidate (do not invent): R2 QTc, R3 clinician-supplied
dose arithmetic (mg/µg, volume, concentration, rate, time-unit dosing), R4+
catalog expansion, drug-specific dosing, pediatric calculators, or any
autonomous recommendation path.

## Result lifecycle (engineering safety; not clinical activation)

Working results use a current/stale session model: any input, unit, Dynamic Type,
or surface-abandon change marks a prior result stale (or clears it) so it cannot
be prepared/exported as a **current** calculation. Provenance (formula IDs,
Draft status, calculated-at, normalized inputs) remains visible. **Formula
activation for clinical care still requires independent pharmacist/clinical
review (P-008) and is not implemented by this lifecycle.**
