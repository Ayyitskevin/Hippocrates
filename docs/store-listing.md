# App Store listing and submission notes

This is the owner's checklist and copy source for submitting Hippocrates to the
App Store as a free app. Nothing here is submitted automatically; every App
Store Connect action is a human step (A-009).

**Submission hold:** this listing is not release-ready while RXcalc remains
`.draft`. Exact-head engineering evidence, the full device script, P-008, P-009,
and explicit owner authorization must all be recorded before any submission.

## Name

"Hippocrates" is a common name in medical software. **Before reserving the
name in App Store Connect, verify availability and check for confusing
collisions.** The binary/bundle identifier need not change regardless.

Candidate display names, in preference order:

1. **Hippocrates** — if available and uncontested.
2. **Hippocrates Ledger** — narrows the meaning to the product.
3. **Pharmacist's Ledger** — descriptive fallback, no name collision.

Subtitle (30 characters max): `Offline pharmacist workspace`.

## Description

This copy is provisional and makes no autonomous clinical-decision claim. It may
be submitted only after exact-head engineering evidence, device acceptance,
immutable P-008 clinical approval, and P-009 regulatory/claims review:

> Hippocrates is a private, offline ledger for hospital pharmacists. Record the
> interventions you have already made in three taps, resolve their outcomes
> later, and hand your manager a clean summary and CSV at review time.
>
> Preserve the drug-information questions you have already answered — with your
> search strategy, structured citations, and follow-up — in a vault that marks
> each answer's verification date and warns you before you rely on one that has
> gone out of date.
>
> RXcalc performs only named, source-identified formulas from values you enter.
> It shows the formula version, units, limitations, and review status; it does not
> choose an input or dose, interpret a result, diagnose, or recommend care.
>
> Everything stays on your device. Hippocrates has no account, no server, and no
> network connection of any kind. It stores no patient identifiers. Your durable
> records are yours: export a complete backup whenever you want. RXcalc inputs and
> results are not retained.
>
> Hippocrates is free, with no ads and no in-app purchases.
>
> You are responsible for following your institution's policies on personal
> devices and professional documentation. Hippocrates cannot verify hospital
> policy and is not a substitute for it.

## Keywords

`pharmacist, pharmacy, clinical, intervention, drug information, hospital,
formulary, preceptor, residency, offline`

## Privacy label — the differentiator

Publish **Data Not Collected** only after the owner verifies the exact release
build and answers the then-current App Store Connect questionnaire. The repository
is designed to support that answer: it has no networking code, the boundary
scanner enforces the source contract, and `PrivacyInfo.xcprivacy` declares no
tracking and no collected data types. Do not add an SDK, analytics, or any other
behavior that makes the answer false.

## Category and age

- Primary category: **Medical**, subject to the completed P-009 assessment and
  then-current App Store requirements. Category selection never substitutes for
  regulatory/claims review.
- Age rating: complete the then-current questionnaire truthfully for the exact
  release build.

## Support and marketing URLs

Provide a stable support URL and a plain-language privacy page before submission.
Verify the then-current App Store URL and privacy-policy requirements for the
exact category, age rating, claims, and release build; do not assume the **Data
Not Collected** answer removes either obligation.

## Pricing

Free. No in-app purchases. No subscriptions.

## Screenshots

Required per device size. Capture on a real device or simulator in airplane mode,
showing: first-run responsibility notice; three-tap capture; recent-ledger outcome
resolution; summary; DI freshness; the RXcalc catalog; and an RXcalc result with
its draft/review badge, formula identifier, units, and adjacent limitation all
visible. Use only fictional, non-identifying values and category names.

## Remaining owner-only actions

These are external gates; none is performed by this repository.

- App icon art (see [`docs/app-icon.md`](app-icon.md)).
- Apple Developer Program enrollment and signing identity.
- Bundle identifier confirmation (`com.ayyitskevin.hippocrates` is set in the
  project).
- Marketing version 1.0 / build number (project sets `MARKETING_VERSION = 1.0`).
- On-device acceptance run ([`docs/acceptance-scripts.md`](acceptance-scripts.md)).
- Immutable P-008 clinical approval for the exact RXcalc evidence bundle and
  P-009 regulatory/claims determination.
- TestFlight upload, then App Store submission.
- Publish the **Data Not Collected** privacy label.
