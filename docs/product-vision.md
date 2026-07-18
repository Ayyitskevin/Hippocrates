# Product vision

## The promise

Hippocrates is the private professional ledger a hospital pharmacist can trust
during a shift and years later. It turns two kinds of already-completed work
into durable evidence:

1. interventions, captured in seconds and valuable in aggregate; and
2. drug-information records, written deliberately and valuable one record at a
   time.

It is not a clinical tool. It never computes a patient-specific result, interprets
patient data, recommends therapy, or advises care. It has no network path and no
field for patient identity. Those are product boundaries, not backlog items.

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
and compounding knowledge. Their only domain relationship is intentional: an
intervention can raise a DI question, and a DI answer can accumulate linked
interventions over time. They share a store, search shell, and export system, but
they remain separate models and separate capture experiences.

## Non-negotiable invariants

- `Intervention` has no free-text or patient-identifier property.
- DI free text cannot be saved without the de-identification review gate.
- The shipping app has no networking, account, sync, server, analytics, or SDK.
- Every user path works in airplane mode.
- No feature calculates, interprets, scores, doses, recommends, or advises.
- No hospital protocol or reference database is stored.
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

## Release shape

The first field build ends after editable configuration, five-second intervention
capture, and CSV summary. Real pilot usage then determines capture ordering and
later native surfaces. DI capture and its de-identification gate ship together in
the next build; staleness, search, links, portfolio export, and backup reminders
follow in the specified order.

No TestFlight or App Store submission is automatic. Code may be prepared and
verified autonomously; distribution remains an explicit owner action.

## Explicit non-goals

- clinical calculations or recommendation logic;
- patient, room, encounter, or hospital-system integration;
- CloudKit, accounts, multi-user behavior, or sharing;
- widgets, App Intents, Siri, Action Button, or Control Center in v1;
- notifications, analytics, crash reporting, or third-party dependencies; and
- a generic note-taking model that merges interventions and DI records.
