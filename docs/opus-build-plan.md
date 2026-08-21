# Hippocrates — Opus build plan (v1 close-out and review phase)

Audience: the next Claude Opus sessions (or any capable engineer) continuing
this project. Written 2026-08-21 against merge commit `b1a35a1` (PR #20). This
is the live successor to [`opus-execution-plan.md`](opus-execution-plan.md),
which remains the historical ledger/DI snapshot. The binding working
conventions in that document's "How to work in this repository" section —
the hosted-CI verification model, the scanner co-evolution procedure, and the
branch/PR/evidence conventions — carry forward unchanged and are not repeated
here. The permanent stop conditions in [`roadmap.md`](roadmap.md) apply
verbatim to every workstream below.

## Where the project actually is

Engineering is ahead of both the paperwork and the humans. Every ledger/DI v1
feature (M1–M7) is merged with hosted evidence. RXcalc R0, R1, R1.1, and R1.2
are engineering-verified as Draft. R1.3 safety-verification work has landed on
`main` — typed unit kinds and `RXCalculationProvenance` (`751c060`),
adversarial de-identification coverage (`3584cf0`), corrupt/truncated/partial
restore rejection (`7049796`) via PR #16, and the current/stale result
lifecycle and export gate (`8fac7a7`, fixed forward in `79184b7`) via PR #17 —
but has **no roadmap status row or recorded exit evidence**. PR #20 added a
V1 golden-journey reliability harness (`bc3bc12`), also unrecorded in the
roadmap table.

There are zero open PRs. Every remaining release gate is a human or external
action, not code:

| Gate | Owner | Blocks |
|---|---|---|
| App icon artwork | Owner (Kevin) | Asset-catalog PR, store submission |
| A8 on-device acceptance run ([`acceptance-scripts.md`](acceptance-scripts.md)) | Owner, on hardware | Distribution |
| Manager acceptance of the summary artifact | Owner + external | Distribution confidence |
| P-008 immutable clinical review | Independent qualified reviewers | Any RXcalc-bearing release |
| P-009 regulatory/claims determination | Owner + qualified review | Store copy, any RXcalc-bearing release |
| P-010 next-slice authorization | Owner (product) | R2/R3/R4 planning |
| Apple enrollment, signing, TestFlight, privacy label | Owner | Everything downstream |

The consequence: **more unprompted engineering on `main` is now low-leverage.**
The highest-leverage work is (1) making the evidence ledger true again,
(2) getting the P-008 packet into reviewers' hands at a frozen candidate, and
(3) putting crisp decision material in front of the owner.

## A structural risk this plan corrects: candidate churn

`docs/clinical-review/rxcalc-r1-v1/bundle.sha256` changed in `8fac7a7` and
again in `bc3bc12`. Every merge that touches a path in `bundle-files.txt`
creates a new Draft candidate and invalidates any packet already circulating.
With several agents (claude/grok/codex/sol branches) merging independently,
the review target never sits still, and P-008 review can never complete
against a stable object ID. Workstream B introduces an explicit candidate
freeze; until it lifts, no PR may modify a bundle-listed path.

## Workstream A — make the evidence ledger true again

Docs only; roughly one session. This repository's credibility rests on the
roadmap being an accurate ledger; right now it is stale by three merges.

1. `docs/roadmap.md`: add an R1.3 status row and milestone section citing
   PR #16 (`751c060`, `3584cf0`, `7049796`, `6dfabac`) and PR #17
   (`8fac7a7`, `79184b7`) with the exact green hosted run IDs from the
   Actions history for each merged head. State plainly which R1.3 bullets in
   [`rxcalc-plan.md`](rxcalc-plan.md) are delivered and which (if any) remain.
2. `docs/roadmap.md`: record the V1 golden-journey harness (PR #20,
   `bc3bc12`) with its hosted run, as reliability evidence rather than a
   feature milestone.
3. `docs/rxcalc-plan.md`: move the R1.3 section after R1.2 (it currently
   reads out of delivery order) and attach its exit evidence.
4. `README.md`: refresh the "Current foundation" paragraph to name R1.3 and
   the golden-journey harness, keeping every boundary statement intact.
5. Confirm `Scripts/rxcalc-review-packet.sh --verify` is green at the exact
   head these docs describe.

Exit gate: docs agree with git history commit-for-commit; CI green.

## Workstream B — P-008 candidate freeze and review operations

Mostly docs; one to two sessions. P-008 itself is external — this workstream
removes every obstacle on our side of it.

1. **Freeze the candidate.** After Workstream A merges, declare that head the
   review candidate. Run
   `Scripts/rxcalc-review-packet.sh --commit <full-object-id>` to emit the
   timestamp-free manifest, and record the candidate object ID in
   `docs/clinical-review/rxcalc-r1-v1/reviewer-packet.md`.
2. **Hold the freeze.** While the packet is with reviewers, no PR may touch a
   path listed in `bundle-files.txt`. Queue RXcalc changes on branches. Any
   bundle-touching merge is a conscious owner decision to restart review.
3. **Reviewer onboarding one-pager** (new doc under
   `docs/clinical-review/rxcalc-r1-v1/`): who qualifies as an independent
   reviewer, exactly what they receive, the checklist and signing procedure,
   and — verbatim from the decision register — what a completed review does
   *not* do (no status activation, no distribution authorization).
4. **Activation-architecture ADR (design only).** The decision register
   requires a separately owner-approved architecture before any
   reviewed-status transition can exist: candidate-to-production binding,
   trusted signature evidence, review expiry and withdrawal, and an honest
   runtime-versus-CI trust boundary. Draft that ADR as a document for owner
   review. Do not implement any of it; the implementation is itself a new
   Draft candidate requiring review.

Exit gate: a distributable packet bound to one frozen candidate object ID;
the ADR awaiting owner disposition; CI green.

## Workstream C — decision material for the owner

The owner currently faces one unstated fork and one stated one. Neither may
be decided by an engineering session; both deserve a one-page memo with
honest costs, filed in the repo and recorded in the decision register when
answered.

1. **Release shape (new question; propose it as P-011).** v1.0's contents are
   currently coupled to P-008/P-009 because RXcalc ships in the build. The
   options to put before the owner:
   - **1.0 waits for review** — ship ledger/DI + Draft RXcalc only after
     P-008 and P-009 close. One release, but the store date is hostage to
     external reviewer availability.
   - **Decouple: ledger/DI-only 1.0** — gate RXcalc out of the release build
     and ship on the icon/A8/manager/store gates alone; RXcalc follows in 1.1
     after review. Requires a new reviewed build-configuration mechanism (the
     scanner pins build configs and scheme XML, so a release-exclusion seam
     is real engineering with its own probes), plus a P-011 register row.
   - **Hold everything** — no release until all gates close. Zero extra
     engineering, maximum calendar risk.
   The memo should state plainly that decoupling trades one-time engineering
   for schedule independence, and that P-009's claims review is likely
   simpler for a build with no clinical formulas.
2. **P-010 (already on the register).** Which post-R1 hypothesis, if any,
   enters planning: R2 QTc, R3 dose arithmetic, R4 favorites, or hold. The
   memo should note the safe-state default (hold) and the cost ordering:
   R2 is stateless and R1-shaped; R4 requires the first persisted-state,
   schema, backup, and privacy change RXcalc has ever made; R3 carries the
   heaviest clinical surface and its own usability-review precondition.
3. **Owner gate checklist**, one page: icon artwork spec pointer
   ([`app-icon.md`](app-icon.md)), the A8 device script run, manager
   acceptance, Apple enrollment/signing, and the **Data Not Collected**
   privacy label — each with what unblocks the moment it closes.

Exit gate: memos merged; decisions remain visibly open until the owner
records them in the register with authority, date, and provenance.

## Workstream D — post-decision engineering (conditional; do not start early)

- **Icon artwork arrives** → the Phase 8 asset-catalog PR: extend the
  scanner's sole-resource rule to an explicit two-item allowlist with pinned
  contents semantics, per the prior plan.
- **P-011 = decouple** → design and implement the reviewed release-exclusion
  seam for RXcalc with scanner probes proving the release configuration
  cannot silently re-include it — its own PR and evidence entry.
- **P-010 = R2** → the QTc slice per [`rxcalc-plan.md`](rxcalc-plan.md),
  as a fresh candidate cycle with primary-source vectors.
- **P-008 record arrives signed** → nothing activates. Verify the record
  against the frozen manifest, file it as provenance, and put the ADR's
  implementation decision in front of the owner.

## What not to do

- No further speculative hardening rounds (an F18 and beyond) without a named
  defect or a red-team finding; the scanner is at 299 checks and the open
  gates are human, not mechanical.
- No R2/R3/R4 implementation before P-010 is recorded. No schema, backup
  format, or persisted-state change of any kind — R4 is the only slice that
  could ever require one, and only after its own reviewed design.
- No new feature surfaces, no drug or protocol content (permanently out),
  no networking-adjacent capability, no relaxation of any non-negotiable.
- No merges into bundle-listed paths while the Workstream B freeze holds.
- No TestFlight, App Store, signing, or privacy-label action from any
  session, ever — owner actions only.

## Sequencing

A first (one session), then B and C in parallel (B is docs plus one script
run; C is pure writing). D items start only when their trigger fires. After
every merged PR: roadmap evidence entry where applicable, green hosted run
cited, owner review before the next workstream advances. When anything below
appears to conflict with the non-negotiables in the README or the roadmap's
permanent stop conditions, the non-negotiables win — stop and flag it in the
PR instead of improvising.
