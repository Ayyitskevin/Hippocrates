# Product vision

## The promise

Hippocrates is the private professional workspace a hospital pharmacist can
trust during a shift and years later. It has three deliberately separate work
surfaces:

1. interventions, captured in seconds and valuable in aggregate;
2. drug-information records, written deliberately and valuable one record at a
   time; and
3. RXcalc, a source-backed set of offline formulas whose inputs and results are
   never persisted.

The first two surfaces create durable evidence; RXcalc supplies transient,
auditable arithmetic.

RXcalc computes only the named equation from clinician-entered values. It does
not select a drug, choose a patient-specific input strategy, interpret a result,
recommend therapy, or advise care. Hippocrates has no network path and no field
for patient identity. Those remain product boundaries, not backlog items.

Hippocrates is distributed free: no purchase price, no subscription, no ads, no
accounts, and no analytics, ever, for v1. There is no server and therefore no
marginal cost per user; the only recurring cost is the owner's Apple Developer
membership. "Free" is a product boundary of the same rank as "offline."

## The user and their jobs

The user is a hospital clinical pharmacist using one current iPhone, often with
poor signal and one hand available. One working pharmacist remains the design
pilot; the shipped app serves any pharmacist with the same jobs.

### During a shift

They need to record an intervention in under five seconds without typing. The
record exists to support later counts, acceptance rates, cost-avoidance totals,
and service-line summaries. An individual intervention is not a narrative chart.

They also need fast access to a small, curated set of transparent calculations
without relying on signal. Every result must show which equation produced it,
which units were used, and what the equation cannot establish.

### After a shift

They need to preserve a drug-information question, the de-identified context
they used, their completed answer, search strategy, structured citations, and
follow-up.
The record must advertise its verification date and become visibly stale rather
than quietly looking current forever.

### At review and precepting time

They need artifacts that are useful without cleanup: a printable intervention
summary, CSV data, and a structured DI portfolio. A complete JSON backup protects
the underlying asset.

## Product thesis

The intervention ledger proves breadth and impact; the DI vault preserves depth
and compounding knowledge; RXcalc supplies ephemeral, auditable math. The
ledger and DI vault share a store, search shell, and export system, but remain
separate models and capture experiences. RXcalc does not join that store or
backup graph. Its only relationship to the durable features is navigation.

## Non-negotiable invariants

- `Intervention` has no free-text or patient-identifier property.
- DI free text cannot be saved without the de-identification review gate.
- The shipping app has no networking, account, sync, server, analytics, or SDK.
- Every user path works in airplane mode.
- RXcalc formulas are deterministic, versioned, source-backed, stateless, and
  isolated from SwiftData.
- No feature chooses a dose, interprets a result, recommends therapy, or advises
  care.
- No hospital protocol, formulary, dosing table, or reference database is stored.
- RXcalc never requests or retains patient identity or free-text clinical context.
- SwiftData schemas are versioned and migrations are explicit from the first
  release.
- A backup is not complete until import and lossless round-trip behavior are
  tested.
- A stale DI answer never looks fresh.

## Success measures

Hippocrates intentionally contains no analytics. Success is measured through
tests and direct acceptance sessions, not telemetry.

| Outcome | Evidence |
|---|---|
| Five-second capture | The pilot user completes ten representative entries one-handed on their phone; median and worst case are recorded manually |
| Offline integrity | Every acceptance script passes in airplane mode; the build boundary rejects planted networking code |
| Schema privacy | The persisted `Intervention` property allowlist and model-schema tests reject text/identifier additions |
| Durable ownership | A populated store exports, restores into a clean installation, and re-exports byte-equivalent logical data |
| Useful annual artifact | The pilot user says the summary is ready to hand to their manager without editing |
| DI freshness safety | Green, amber, and red fixtures render distinctly; amber/red records interpose before answer content every time |
| RXcalc trustworthiness | Official or primary-source golden vectors, unit-equivalence tests, invalid-input tests, and an independent clinical review cover every active formula version |

## Release shape

The ledger and DI v1 surfaces are implemented; their real-device and owner
acceptance gates remain open. RXcalc R1 is the draft calculation slice. R2-R4
are unstarted and outside the current v1 release, while drug-specific content is
outside the product unless a new owner/doctrine decision explicitly reopens it.

RXcalc engineering completion does not authorize use or distribution. Device
acceptance, immutable P-008 clinical approval, P-009 regulatory/claims review,
and every TestFlight or App Store action remain separate human/external gates.

## Explicit non-goals

- drug-specific dosing, treatment recommendations, or hidden clinical
  interpretation;
- uncited, unversioned, or externally fetched calculator content;
- pediatric, time-critical, narrow-therapeutic-index, chemotherapy,
  anticoagulation, insulin, opioid, electrolyte, or compounding calculators in
  the first RXcalc release;
- persisted calculator inputs, results, favorites, or history without a separate
  schema/backup/privacy decision;
- patient, room, encounter, or hospital-system integration;
- CloudKit, accounts, multi-user behavior, or sharing;
- widgets, App Intents, Siri, Action Button, or Control Center in v1;
- notifications, analytics, crash reporting, or third-party dependencies; and
- a generic note-taking model that merges interventions and DI records.
