# Hippocrates — hospital pharmacist workflow review

> **Historical snapshot:** these findings describe commit `5f62977`. Current
> status and gates live in [`roadmap.md`](roadmap.md). This review predates RXcalc
> and provides no clinical approval for any RXcalc formula or release claim.

Date: 2026-07-18. Reviewed at commit `5f62977` by a full read of the source,
tests, scanner, CI workflow, and all four project documents. Perspective: a
hospital clinical pharmacist who would use this app every shift, plus a product
assessment of the owner's new direction — a free, general-audience app for
pharmacists rather than a single-user personal tool.

## Where the project actually stands

The repository contains an exceptional engineering foundation and **zero
user-facing product**. By line count: roughly 7,150 lines of boundary scanner,
about 3,100 lines of tests, and under 1,000 lines of shipping app code — of
which the entire visible UI is one placeholder `Text` view
(`Hippocrates/App/RootView.swift`). Seventeen foundation-hardening milestones
(F0–F17) are verified; Milestones 1–7 (every screen a pharmacist would touch)
are all still ahead.

This is not wasted work. The schema, backup format, migration plan, restore
rollback, and privacy enforcement are the parts that are catastrophic to get
wrong after release, and they are done to a standard almost no indie health app
reaches. But the review below should be read with that frame: the foundation
deserves an A; the product a pharmacist can hold today does not yet exist.

## What the design gets right for a working pharmacist

**Three-tap capture is the correct core loop.** On the floor you have one hand,
gloves, interruptions, and about five seconds between tasks. Every intervention
tracker that failed before (paper cards, Excel on a workstation, EHR i-Vents)
failed because capture cost more than the intervention felt worth. Type → drug
class → acceptance with no required typing is exactly right.

**No PHI by design is the killer feature, not a limitation.** `Intervention`
physically cannot hold free text or an identifier — that is enforced by the
schema, the tests, and the build scanner. This removes the number-one reason a
hospital pharmacist cannot use a personal app at work, and it makes the App
Store "Data Not Collected" label truthful and provable from source. In
healthcare software, that is a genuine differentiator worth building the entire
marketing story around.

**Offline-first matches hospital reality.** Basements, stairwells, lead-lined
walls, dead Wi-Fi zones. Every path working in airplane mode is the right bar.

**The data captured is the currency of the profession.** Intervention counts,
acceptance rates, cost avoidance, and service-line breakdowns are what annual
reviews, clinical-service justifications, and residency portfolios are made of.
A CSV and a printable summary a manager will accept without cleanup is the real
deliverable.

**The DI vault with staleness decay is genuinely innovative.** Nothing
mainstream marks a drug-information answer as stale. Answers rot — a
compatibility answer from 2023 is a liability in 2026. Per-record
green/amber/red freshness with a blocking interstitial before stale content,
append-only re-verification history, and structured citations by source tier is
a preceptor's dream and, to my knowledge, a first in this category.

## Workflow gaps the plan must fix

**1. Pending acceptance can never become accepted (the biggest gap).** A
pharmacist usually does not know the outcome at capture time — you make the
recommendation on rounds and learn hours or a day later whether it was
accepted. The schema's `pending` default handles capture correctly, but current
doctrine forbids any intervention detail or edit screen, and undo lasts five
seconds. As designed, a `pending` record is frozen forever, which guarantees
either a wrong acceptance rate or pharmacists guessing at capture time. The
execution plan resolves this with a bounded, no-free-text "recent entries"
resolution surface (new decision I-013): structured-field edits and acceptance
flips only, never narrative.

**2. No correction path for fat-fingered entries.** Tap the wrong drug class at
hour eleven of a shift and the record is permanently wrong after five seconds.
Dirty data quietly destroys trust in the summary numbers — the artifact the
whole app exists to produce. Same fix as above: bounded structured editing plus
a reviewed, confirmed delete path.

**3. End-of-shift reconciliation.** "Did I log that vancomycin consult?" needs
an at-a-glance answer. The same bounded recent-entries view covers this; it
must remain a ledger view, not a narrative chart.

**4. Backup is the only thing standing between a pharmacist and losing years of
evidence.** One device, no sync, no server. Phones are lost, dropped in
toilets, and replaced every two years. The manual JSON backup with a 90-day
reminder is the right v1 mechanism, but it must be prominent (surfaced in
settings and via reminder, exercised in onboarding language) — not an expert
feature buried at the bottom.

**5. Night shift crosses midnight.** Date-range summaries bucket by calendar
day. A 19:00–07:30 shift's entries split across two days. Not a v1 blocker —
range totals are what managers read — but worth a note as a known limitation
rather than a surprise.

## Assessment of the pivot: personal tool → free general-audience app

The owner's direction (2026-07-18): a free-install, no-charge, easy-to-use,
innovative app for pharmacists — "micro-SaaS" polish without a price tag. The
economics work precisely because of the architecture: no server, no accounts,
no sync means zero marginal cost per user. The only recurring cost is the Apple
Developer membership. Nothing about the offline/no-PHI doctrine needs to change
— it is the moat.

What does have to change is the decision model. The docs currently gate six
product decisions (P-001–P-006) on one named user and her institution. A
general-audience app cannot wait for one hospital's answers; those gates
convert into first-run and settings choices owned by each user:

- **P-001 (hospital policy)** becomes an explicit first-run responsibility
  notice — the app cannot verify any institution's policy; each user affirms
  their own compliance. This also becomes App Store disclaimer language.
- **P-002 (cost values)** stays `nil` by default; each user may enter their
  institution's figures per intervention type; exports label them as
  user-configured estimates.
- **P-003 (taxonomy)** becomes: empty editable taxonomies plus an *explicitly
  offered, reviewable, skippable* ASHP-derived starter set at first run. No
  silent seeding — the user sees the list and chooses.
- **P-004 (summary range)** becomes a visible, user-changeable range control
  defaulting to the current calendar year.
- **P-005 (staleness)** becomes a required first-DI-use choice: 6 months, 12
  months, or custom. The stored value remains `nil` until the user picks —
  preserving the existing "no hidden default" doctrine for all users.
- **P-006 (DI vocabulary)** ships frozen as-is; every enum already carries an
  `other` escape hatch, which is the correct general-audience answer.

The audiences, in priority order: hospital staff/clinical pharmacists (daily
intervention logging), PGY1/PGY2 residents (intervention and DI documentation
are program requirements — this cohort has an acute, recurring need and high
word-of-mouth density), pharmacy students on APPE rotations, and preceptors
(the DI vault doubles as a teaching portfolio).

## Engineering risk the plan must manage

The 7,159-line boundary scanner pins the project file, every source path,
imports, string interpolation, resources, and schemes. It is the reason the
privacy claims are provable — keep it. But it means **every feature commit
co-evolves the scanner allowlists**, and CI probes grep for exact diagnostic
strings. Untracked, this becomes a velocity tax that stalls feature work; the
execution plan therefore gives an explicit scanner co-evolution procedure and
budgets it into every phase rather than treating it as friction to discover.

One naming note: "Hippocrates" is common in medical software. Before listing,
check App Store name availability and obvious collisions; have one or two
alternates ready. The binary/repo name need not change either way.

## Verdict

Foundation: keep everything, change nothing structural. Product: execute
Milestones 1–7 with the general-audience conversions above, add the
pending-resolution ledger (I-013), then do App Store readiness work
(icon/accessibility/listing) that the current roadmap does not yet cover. The
full sequenced instructions live in
[`docs/opus-execution-plan.md`](opus-execution-plan.md).
