# RXcalc R1 claims and policy matrix

Status: engineering review aid only. Every formula remains Draft. This file is
part of the candidate digest; it is not a clinical approval or a P-009
regulatory determination.

| Formula ID | Population/display claim | Canonical units and rounding | Required independent review |
|---|---|---|---|
| `cockcroft_gault_1976@1.0.0` | Adults 18+ with stable kidney function; unindexed CrCl estimate; entered calculation weight | age years, weight kg, SCr mg/dL → mL/min; one decimal | Original-cohort age range versus app upper bound; female coefficient; stable-function warning; weight-selection disclaimer; no dose/stage inference |
| `ckd_epi_creatinine_2021@1.0.0` | Adults 18+; race-free creatinine-only indexed eGFR | age years, SCr mg/dL → mL/min/1.73 m²; whole number | Exact constants/branches; standardized creatinine; equation-sex copy; indexed-result limitations; no stage/de-index/dose inference |
| `body_mass_index_cdc_metric@1.0.0` | Adults 20+; BMI calculation without category or treatment interpretation | age years, height cm, weight kg → kg/m²; two decimals | Adult age boundary; exact SI conversion versus rounded CDC US expression; no body-composition interpretation |
| `body_size_mosteller_1987@1.0.0` | Adults 20+ body surface area estimate without dose derivation | age years, height cm, weight kg → m²; two decimals | Lawful authoritative formula artifact; formula transcription; no protocol, cap, or dose implication |

## Non-runtime candidate reviewed-state wording

The following exact strings are review aids only and exist only in this packet.
No production target contains a constructible reviewed status or code path that
can display them:

- Status: “Reviewed — independent clinical review recorded”
- Catalog heading: “Clinical review recorded”
- Catalog notice: “Independent clinical review is recorded for this exact
  formula bundle. Regulatory, release, and local-policy review remain separate;
  RXcalc does not select inputs, interpret results, or recommend therapy.”
- Result notice: “Independent clinical review is recorded for this exact formula
  bundle. Verify patient-specific inputs, units, current labeling, and local policy.”

Reviewers may approve or require changes to this future wording. Any runtime
representation or binding mechanism requires a separately owner-approved design.

P-008 does not answer P-009. No P-008 disposition may authorize TestFlight,
App Store submission, field use, or public distribution by itself.

## Result provenance and human-review boundary (engineering)

Successful calculator results expose a structured provenance object used for
reproducibility and UI labeling. Engineering fields (not clinical claims):

| Field | Contract |
|---|---|
| `formulaIdentifiers` | Exact catalog formula version string(s) for the path taken |
| `roundingPolicyIdentity` | Stable display-only policy id; arithmetic retains full precision |
| `sourceReviewStatusTitle` | Always Draft wording until a future activation design exists |
| `humanReviewRequired` | Always `true` for shipped R1 |
| `isAutonomousClinicalRecommendation` | Always `false` — arithmetic only; no dosing advice |
| `calculatedAt` | Timestamp of the successful calculation |
| `inputTraces` | Original entered values/units and normalized canonical values/units |

These fields support independent verification. They are not a clinical approval
and must not be read as autonomous recommendations.
