# RXcalc R1 reviewer packet

Packet version: `rxcalc-r1-review-record-v1`

Status: template and engineering evidence map. No clinical reviewer has signed
this packet, no formula is approved, and the app remains Draft.

## Exact candidate scope

The packet covers only:

- `cockcroft_gault_1976@1.0.0`
- `ckd_epi_creatinine_2021@1.0.0`
- `body_mass_index_cdc_metric@1.0.0`
- `body_size_mosteller_1987@1.0.0`

It binds the formula implementations, catalog metadata, canonical units,
rounding, limitations, and non-runtime candidate reviewed-state wording in
`claims-and-policy-matrix.md`, plus UI adjacency, unit and dedicated catalog
Dynamic Type UI tests, architecture
scanner, CI controls, integration notices, release copy, and governance
documents enumerated by `bundle-files.txt`.

## Deterministic evidence

`bundle.sha256` is the CI-enforced worktree content manifest. It excludes itself
to avoid recursive hashing; the closed packet directory permits only that one
derived exception, while requiring every other packet artifact in the exact
allowlist. `Scripts/rxcalc-review-packet.sh --verify` fails on bundled drift,
malformed allowlists, or undeclared RXcalc and packet entries. CI plants each
class of violation and requires stable rejection diagnostics.

A reviewer generates the candidate manifest from Git objects, not the working
tree. Its digest is embedded in the exact reviewer-record bytes that are later
signed:

~~~sh
git switch --detach <full-candidate-sha>
Scripts/rxcalc-review-packet.sh --verify
Scripts/rxcalc-review-packet.sh   --commit <full-candidate-sha>   --output /secure/path/rxcalc-r1-candidate.tsv
shasum -a 256 /secure/path/rxcalc-r1-candidate.tsv
~~~

The candidate manifest has no generated timestamp. It records the exact commit,
class, Git mode, byte length, SHA-256, and path in bytewise order. Every path is
immutable for that Draft candidate. Each finalized reviewer record binds that
root digest, the external evidence-manifest digest, reviewer assertions, and its
predeclared external signature locator. The packet cannot change runtime review
status.

## Evidence map

- Source metadata and unresolved lawful-artifact gaps:
  `source-provenance.json`
- Independently reviewable engineering vectors and test mapping:
  `golden-vectors.json`
- Display claims and policy questions: `claims-and-policy-matrix.md`
- Reviewer roles, signature, cadence, and candidate-review procedure:
  `reviewer-checklist.md`
- Machine-readable reviewer-record requirements: `packet-schema.json`
- Explicit no-activation boundary: `activation-boundary.json`

External evidence should include lawful source snapshots/digests, exact-head CI
evidence, the Accessibility 5 `.xcresult` or its durable external locator and
digest, a human review record for its kept screenshots, and the dated device A8
record. Simulator evidence is supplemental: device A8 is a separate release gate
and may remain pending during formula review, but it cannot be omitted before
field eligibility or distribution.

`packet-schema.json` validates record structure and role-specific formula
coverage only. It cannot compare dates, resolve Git objects, hash external
artifacts, verify credentials, or perform cryptographic verification; the
trusted external checks in `reviewer-checklist.md` are mandatory.

## Current blockers

The source-provenance artifact digests, exact-head Accessibility 5 result
evidence, human screenshot review, reviewer qualifications, dispositions,
signatures, accepted keys and verification procedure, cadence, next-review date,
P-009 determination, physical-device A8, and owner distribution authorization
are all pending. A trusted, executable reviewed-candidate-to-production and
continuing-build binding design is also absent, so the app has no production
activation path and remains Draft even if reviewers complete this candidate
record.

Completing this template or producing a digest does not close any of those
gates or authorize patient care, signing, TestFlight, App Store submission, or
distribution.
