# Hippocrates — execution plan (start to finish)

Audience: the Claude Opus session (or any capable engineer) that will carry
this project from its current state — verified foundation, zero user-facing
product — to a free, App Store-ready app for hospital pharmacists. Companion
review: [`docs/pharmacist-review.md`](pharmacist-review.md). Written
2026-07-18 against commit `5f62977`.

## Mission

Ship Hippocrates v1 as a **free, offline, no-account iOS app** any hospital
pharmacist can install and use daily: three-tap intervention capture, a
manager-ready summary export, a drug-information vault with staleness decay,
and a lossless JSON backup. No charge, no ads, no analytics, no server —
distribution-quality polish with zero marginal cost per user.

## Non-negotiables (unchanged from the existing doctrine)

These survive the pivot to a general audience exactly as written in
`README.md`, `docs/product-vision.md`, and the roadmap's permanent stop
conditions:

- No networking, CloudKit, accounts, sync, analytics, crash reporting,
  notifications, widgets, or third-party packages. Zero SPM dependencies.
- `Intervention` never gains a free-text or identifier property.
- No feature calculates, doses, scores, interprets, recommends, or advises.
- DI free text never saves (and never restores) without the de-identification
  gate.
- Every user path works in airplane mode.
- SwiftData schemas stay versioned; released schemas are immutable.
- The boundary scanner stays. It is extended deliberately, never bypassed.
- TestFlight/App Store submission is a human (owner) action, never automated.

If any instruction below ever appears to conflict with these, the
non-negotiables win; stop and flag it in the PR instead of improvising.

## How to work in this repository

### Verification model

- The remote/Linux dev environment **cannot build or test the iOS app** — no
  Xcode, and in most containers no Swift toolchain. All Apple-platform
  verification happens on the hosted GitHub Actions workflow
  (`.github/workflows/ios-ci.yml`, macOS 15, Xcode 16.4, iOS 18.5 simulator).
- Workflow per unit of work: small commits on a feature branch → push → open or
  update a draft PR → watch the `iOS CI` run → treat red as blocking and fix
  before stacking more work.
- Follow the established evidence convention: when a phase completes, update
  the status table and add a milestone section in `docs/roadmap.md` citing the
  implementation commit and the green hosted run, exactly as F0–F17 do.

### Scanner co-evolution procedure (read before every phase)

`Scripts/NetworkBoundaryScanner.swift` (≈7,150 lines, 270 checks at head)
enforces: exact equality between Swift files on disk and the pbxproj Sources
phases; a resource allowlist (currently `PrivacyInfo.xcprivacy` is the *sole*
app resource); a five-framework import allowlist; per-file string-interpolation
allowlists; pinned build configurations and scheme XML; pinned
`AppConfig`/backup/schema seams; and forbidden API surfaces (URL loading, file
pickers, networking, unsafe memory, model deletion, etc.).

Every feature phase therefore includes scanner work. The procedure:

1. **Adding a Swift file**: create it under the correct feature directory,
   add its `PBXFileReference`, `PBXBuildFile`, group child, and Sources-phase
   entries to `Hippocrates.xcodeproj/project.pbxproj`, and add it to the
   sandboxed build phase's declared input list. The scanner's disk↔target
   equality check fails closed until both sides agree.
2. **New imports** (e.g. `Charts` in Phase 3): extend the import allowlist with
   the exact framework, in the scanner, with a comment naming the phase that
   reviewed it.
3. **String interpolation in new UI files**: the allowlist is per-file and
   per-expression. Add entries alongside the file; never widen to a wildcard.
4. **New reviewed seams** (e.g. the Phase 7 file-import adapter, the Phase 2
   ledger edit/delete service): model them on the existing exact-path,
   exact-spelling exceptions (`AppConfigService` authority,
   `SchemaContractTests` URL seams). Narrow, named, commented.
5. **Diagnostics**: if you add or reword a scanner diagnostic, update the two
   CI probe steps in `ios-ci.yml` that grep for exact strings, and keep both
   planted-violation probes failing for the right reasons.
6. **Never** delete checks, broaden a regex to "make it pass," or route around
   the scanner with encodings. If a check is genuinely wrong for the new
   feature, change it in its own commit with the reasoning in the message.
7. When persisted schema or backup shape changes are ever needed (they should
   **not** be for v1 — SchemaV1 already contains every field the v1 feature
   set uses), the scanner's backup-format-review gates will fire; that is the
   architecture working. v1 must ship on SchemaV1 and backup format v2 as-is.

### Conventions

- Branch per phase (`feature/m1-configuration`, etc.), draft PR early, evidence
  links in the PR description.
- Match the existing code style: doc comments explain SwiftData semantics and
  invariants, not narration. Pure policy types live outside SwiftUI. Services
  are `@MainActor` where they touch `ModelContext`.
- New directories follow `docs/architecture.md`'s layout (`Features/Capture`,
  `Features/Summary`, `Features/DIVault`, `Features/Settings`, `Safety/`,
  `Services/`, `Export/`). Create each directory only when its phase begins.
- Tests first-class in every phase: pure policy tests, SwiftData in-memory
  tests, and (where the seam exists) file-backed tests, extending the existing
  suites' patterns.

---

## Phase 0 — doctrine re-scope (docs only, no code)

Goal: make the repository's own documents agree with the owner's 2026-07-18
direction so later phases aren't contradicting the paperwork.

1. `docs/product-vision.md`: re-scope from "one pharmacist (Jenn)" to "any
   hospital pharmacist"; keep every invariant. Add the free-distribution
   stance: free install, no charge, no ads, no accounts, ever, for v1.
2. `docs/decision-register.md`: record the pivot and convert the six product
   gates into user-owned choices, as accepted product decisions with deciding
   authority "owner (Kevin)", date 2026-07-18, provenance "owner direction,
   recorded in the PR that introduced this plan":
   - P-001 → first-run responsibility notice; user affirms institutional
     compliance; app never claims to verify policy.
   - P-002 → cost defaults remain `nil`; user-configurable per type; exports
     label figures as user-configured estimates.
   - P-003 → empty taxonomies plus an explicitly offered, reviewable,
     skippable ASHP-derived starter set at first run. No silent seeding.
   - P-004 → summary range is a visible control; initial state = current
     calendar year; the user's last selection is remembered (ephemeral
     UI-state persistence via `AppStorage` is acceptable; it is not clinical
     data).
   - P-005 → per-user required choice (6 / 12 / custom months) at first DI
     use; `AppConfig.stalenessIntervalMonths` stays `nil` until chosen.
   - P-006 → frozen vocabulary ships as-is (every enum has `other`).
   Also record new implementation decisions:
   - **I-013 (new)**: a bounded recent-interventions ledger permits editing an
     intervention's structured fields (type, drug class, service line,
     acceptance, minutes, cost override) and confirmed deletion, through one
     reviewed service. No free text, no narrative, no per-record notes — the
     no-detail-screen doctrine is amended to "no narrative detail screen."
   - **I-007 (resolve)**: acceptance rate = accepted ÷ (accepted + rejected);
     `pending` and `notApplicable` excluded from the denominator; all four
     counts always displayed and exported alongside the rate; the CSV and
     printable label the denominator rule in text.
   - **I-011 (resolve)**: `lastExportAt` = the moment a full-backup archive is
     successfully generated and handed to the share sheet. Reminder copy says
     "last backup created," never "delivered" or "verified."
   - **I-003 (resolve for v1)**: restore is offered only pre-bootstrap (first
     run) or into a logically pristine store; destructive replacement is out
     of v1.
   - **I-012 (resolve)**: capture is possible when ≥1 active
     `InterventionType` and ≥1 active `DrugClass` exist; service lines
     optional. First-run distinguishes never-configured (show setup gate) from
     intentionally-minimal (user chose to skip starter set) via the explicit
     choice recorded at onboarding.
   - **I-008 (resolve)**: optional service line / minutes / cost-override
     controls live in a collapsed strip above the three required controls;
     collapsed state applies defaults; the required path stays exactly three
     taps. Post-save corrections go through the I-013 ledger.
3. `README.md`: update the one-user framing and the "required decisions"
   section to point at the new register entries; keep every boundary
   paragraph.
4. `docs/roadmap.md`: append a "v1 product execution" section pointing at this
   plan; do not rewrite F0–F17 history.

Exit gate: docs are internally consistent; no code changed; CI green
(docs-only commits still run CI — it must stay green).

## Phase 1 — first-run, settings, and taxonomy ownership (Milestone 1)

Goal: a clean install can be configured to the point where capture is possible.

Build:

- `Features/Settings/` — taxonomy editors for intervention types, drug
  classes, service lines: add, rename, reorder (`sortOrder`), soft-deactivate
  (`isActive = false`) for referenced rows; hard delete only for
  never-referenced rows, through a reviewed deletion seam (scanner exception,
  modeled on the pending-delete fixture). Per-type optional cost default entry
  (P-002), stored in cents, `nil` ≠ 0 visibly preserved ("Not set" vs "$0").
- First-run gate (this is the architecture's sanctioned pre-bootstrap
  exception): responsibility notice (P-001) → starter-taxonomy offer (P-003:
  show the full ASHP-derived list on screen, user accepts all / edits
  selection / skips) → done → straight into capture. Subsequent launches go
  directly to capture (I-012 predicate).
  - The starter list ships as a Swift constant (no bundled data file — keeps
    the sole-resource rule and the scanner untouched on resources). Keep it
    modest (12–20 intervention types, e.g. renal dose adjustment, IV→PO,
    therapeutic duplication, antimicrobial de-escalation…; common drug
    classes; common service lines) and factually neutral.
- `AppConfigService` already covers configuration creation; wire it into
  bootstrap. Staleness interval UI does **not** ship here (Phase 5).
- Restore-from-backup gets a visible "Restore a backup" affordance on the
  first-run gate but remains disabled/stub until Phase 7 (label it "coming in
  a later step" honestly or hide behind the Phase 7 flag — do not wire
  unguarded import).

Tests: taxonomy soft-deactivation vs delete rules; referenced-row protection;
bootstrap predicate (never-configured vs minimal vs restored); backup
round-trip still lossless after every configuration mutation (extend the
existing suites).

Exit gate (mirrors Milestone 1): clean install contains no invented values
without explicit user acceptance; all three taxonomies configurable; round-trip
lossless; CI green with scanner extended for the new files.

## Phase 2 — five-second capture + the ledger (Milestone 2 + I-013)

Build:

- `Features/Capture/` — launch-to-capture screen, bottom-anchored thumb-reach
  controls: type → drug class → acceptance; third tap saves immediately with
  light haptic; five-second undo snackbar (UUID + cancellable task, per the
  architecture doc); collapsed optional strip per I-008.
- `Services/FrecencyRanking` (pure, no SwiftUI import): rank active types from
  a bounded recent window (frequency + last-used, `sortOrder`/label
  tie-breakers), unit-tested with deterministic fixtures. Bounded fetches
  only — no unbounded `@Query` on the capture screen.
- `Features/Capture/RecentLedgerView` + `Services/InterventionLedgerService`
  (I-013): last 50 interventions, newest first; each row shows time, type,
  class, service line, acceptance chip; tap → structured-field edit sheet
  (pickers only, no text); acceptance one-tap flip from the row; delete with
  confirmation. The service owns all mutation/deletion; scanner gains its
  reviewed edit/delete seam here.

Tests: ranking policy; save-transaction and undo behavior (in-memory
SwiftData); ledger edit/delete transactions; snapshot of the I-008 default
application.

Exit gate: three taps to save in the simulator; undo works; pending→accepted
flip works from the ledger; CI green. The real-device "ten entries one-handed
under five seconds each" acceptance is an owner action — record it in the
roadmap as an open human gate, don't fake it.

## Phase 3 — summary and CSV/printable export (Milestone 3)

Build:

- `Features/Summary/` — selectable date range (default current calendar year,
  last selection remembered); counts by type and by month; acceptance rate per
  I-007 with all four counts displayed; cost-avoidance total (labeled
  user-configured estimate; omit the line entirely when all values are `nil`);
  top drug classes; service-line breakdown.
- `Export/` — deterministic RFC 4180 CSV (versioned column order,
  locale-independent, formula-injection neutralization per the architecture
  doc — the design is already specified there, implement it exactly);
  printable summary via Swift Charts (`import Charts` — first-party; extend
  the scanner import allowlist) rendered through `ImageRenderer` into a
  shareable PDF `Data`; `ShareLink` with `Transferable` app-owned `Data`
  only — never a URL.
- Main-actor snapshot → `Sendable` DTO → off-main formatting, per the
  architecture's export rules. Summary/portfolio exports must not touch
  `lastExportAt` (I-011).

Tests: date-range boundaries (month/year edges, leap day); denominator policy;
CSV quoting/injection fixtures; deterministic byte-equality on repeated export
of the same snapshot.

Exit gate: simulator-generated CSV opens clean in a spreadsheet; printable
renders; CI green. "Manager would accept it without editing" stays an open
human gate in the roadmap.

## Phase 4 — DI capture and the de-identification gate (Milestone 4)

Build:

- `Safety/` first, pure and SwiftUI-free: `DeidentificationScanner` producing
  findings (field, range, category, matched text) for the specified patterns —
  MRN-like numbers, dates, room/bed patterns, phone numbers, ages > 89, and
  the literal fixture set from the milestone; exhaustive regex fixtures, both
  matching and non-matching (drug names, doses like "5 mg", NDC-adjacent
  numbers must NOT false-positive — build the negative fixture list as
  carefully as the positive one).
- `Features/DIVault/` — multi-step durable draft (draft = saved `DIQuestion`
  with `answeredAt == nil`); structured sections (question, background,
  classification enums, search strategy, response, references, follow-up);
  structured citations by tier with title/locator/accessed date/optional URL
  string (text only — the scanner's no-URL-type rules stay intact).
- Save boundary exactly as `docs/architecture.md` specifies: scan the four
  guarded fields together; blocking review sheet; per-finding Remove /
  "Not an identifier"; acknowledgements are per-save-attempt, invalidated by
  edits. Wire the same gate into `BackupService` restore acceptance for DI
  text (guard-on-import), because Phase 7 will expose restore.
- Per I-009: tags and citation title/locator get length-limited single-line
  input and pass through the same scanner before save; document this in the
  register as the I-009 resolution.
- `verifiedOn` editable at creation, `reviewAfter` derived from the chosen
  interval; both already invariant-checked by the model.

Tests: every regex fixture; acknowledgement invalidation on edit; draft save
offline; gate-on-import parity (an archive with a planted MRN in
`questionText` requires the gate before restore completes).

Exit gate: Milestone 4's — fixtures block, nothing silently scrubbed or
permanently ignored, clean drafts save offline; CI green.

## Phase 5 — freshness and retrieval (Milestone 5)

Build:

- `Services/FreshnessPolicy` (pure): draft precedence
  (`answeredAt == nil` → draft), green through `reviewAfter`, amber after it,
  red after one additional per-record `reviewAfter − verifiedOn` interval —
  the model and architecture already define this; implement and test the
  boundaries exactly (the instant of transition, DST, leap years).
- First-DI-use staleness choice (P-005): 6 / 12 / custom months, stored via
  `AppConfigService.setStalenessIntervalMonths`; changing it later affects new
  verifications only (per-record intervals already guarantee this).
- Amber/red interstitial before answer content, every presentation,
  view-local dismissal only. One-tap re-verify calling `DIQuestion.reverify`
  (already transactional, append-only).
- In-memory lowercased full-text search over the DI set; freshness badge on
  every result row.

Tests: boundary dates both transitions; interstitial interposition
(ViewInspector-style or view-model-level given no UI-test target — match
strategy #4's intent at the view-model layer); search relevance basics.

Exit gate: Milestone 5's — a red record cannot render green or bypass the
interstitial; CI green.

## Phase 6 — the compounding link (Milestone 6)

Build: "this raised a question" on capture/ledger creates a linked DI draft;
DI detail lists linked interventions with year-aware aggregate language;
delete rules already preserve interventions on question removal (verify, don't
re-implement). Backup round-trip already preserves both directions — extend
the fixture to a multi-year accumulation case.

Exit gate: Milestone 6's restored-fixture proof; CI green.

## Phase 7 — portfolio, restore UI, and backup reminders (Milestone 7)

Build:

- DI portfolio export (formatted document in standard response order,
  `ShareLink`-shared `Data`), reusing the Export layer.
- Full-backup export UI (archive → JSON → share sheet), setting
  `lastExportAt` per I-011 on successful generation.
- Restore UI at the first-run gate (I-003): the narrow I-010 local-file
  adapter — `fileImporter`, `isFileURL` required, security-scoped access
  acquired/released immediately around a single read into app-owned `Data`,
  no other URL behavior. This is the one sanctioned scanner exception for file
  ingress; implement it as an exact-path reviewed seam and update both CI
  probes (which currently *require* file-import surfaces to fail — they must
  now require that only the reviewed adapter passes and everything else still
  fails).
- De-identification gate runs on imported DI text before restore commits
  (wired in Phase 4).
- 90-day dismissible backup reminder off `lastExportAt`; honest best-effort
  first-run note about iOS backup state per A-011.

Tests: adapter contract (rejects non-file URLs; releases scope on every path);
end-to-end export→clean-store→import→re-export logical equality through the UI
service layer; reminder threshold logic.

Exit gate: Milestone 7's clean-install exercise; no raw DI text bypasses the
guard; CI green.

## Phase 8 — App Store readiness

Build/prepare (code and repo items):

- App icon + accent color: an asset catalog is a new app resource — extend the
  scanner's sole-resource rule to an explicit two-item allowlist
  (`PrivacyInfo.xcprivacy`, `Assets.xcassets`) with pinned contents semantics
  (icon set + accent color only). Launch screen via Info.plist keys.
- Accessibility pass: Dynamic Type at largest sizes on capture and summary;
  VoiceOver labels on the three capture controls, acceptance chips, freshness
  badges (color is never the only signal — pair icon/text with amber/red);
  minimum 44pt targets; Reduce Motion respected on the snackbar.
- Display-name/versioning hygiene: marketing version 1.0, build number
  scheme; `CFBundleDisplayName`; check both against the scanner's pinned
  build-configuration allowlists.
- In-repo `docs/store-listing.md`: app name candidates (verify "Hippocrates"
  availability; keep alternates), subtitle, description copy that makes no
  clinical-decision claims (Apple guideline 1.4.1 posture: it's a
  professional record-keeping tool; it does not calculate, recommend, or
  contain drug content), keyword set, support contact plan (a GitHub Pages or
  repo-README support URL is sufficient and free), and the privacy-label
  answer: **Data Not Collected**.
- `docs/acceptance-scripts.md`: the airplane-mode manual scripts (capture ×10
  one-handed, summary export, DI save with planted identifier, backup→wipe→
  restore) for the owner to run on device before submission.

Owner-only actions (list them in the PR; do not attempt): Apple Developer
enrollment, bundle ID/signing, TestFlight upload, App Store Connect privacy
label ("Data Not Collected"), screenshots, pricing = Free, submission.

Exit gate: v1 completion audit section of `docs/roadmap.md` updated with every
automated gate green and the human gates explicitly listed as open until the
owner closes them.

---

## Order, sizing, and stop rule

Phases are strictly sequential (each builds on the previous's surfaces); within
a phase, pure-policy code and tests can land before UI. Expect the scanner/CI
work to be roughly a quarter of each phase's effort — that is normal here, not
a detour. After every phase: roadmap evidence entry, green hosted run, PR
review by the owner before the next phase starts.

Stop and escalate to the owner rather than improvise if: a phase seems to need
a schema change, a new resource type, a new framework beyond `Charts`, any
network-adjacent capability, or any relaxation of a non-negotiable. The
permanent stop conditions in `docs/roadmap.md` apply verbatim to this plan.
