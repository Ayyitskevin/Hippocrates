# App Store listing and submission notes

This is the owner's checklist and copy source for submitting Hippocrates to the
App Store as a free app. Nothing here is submitted automatically; every App
Store Connect action is a human step (A-009).

## Name

"Hippocrates" is a common name in medical software. **Before reserving the
name in App Store Connect, verify availability and check for confusing
collisions.** The binary/bundle identifier need not change regardless.

Candidate display names, in preference order:

1. **Hippocrates** — if available and uncontested.
2. **Hippocrates Ledger** — narrows the meaning to the product.
3. **Pharmacist's Ledger** — descriptive fallback, no name collision.

Subtitle (30 characters max): `Private intervention ledger`.

## Description

Copy that makes no clinical-decision claim (App Store Guideline 1.4.1 posture:
this is a professional record-keeping tool; it does not calculate, recommend,
diagnose, or contain drug content):

> Hippocrates is a private, offline ledger for hospital pharmacists. Record the
> interventions you have already made in three taps, resolve their outcomes
> later, and hand your manager a clean summary and CSV at review time.
>
> Preserve the drug-information questions you have already answered — with your
> search strategy, structured citations, and follow-up — in a vault that marks
> each answer's verification date and warns you before you rely on one that has
> gone out of date.
>
> Everything stays on your device. Hippocrates has no account, no server, and
> no network connection of any kind. It stores no patient identifiers and
> performs no clinical calculations. Your records are yours: export a complete
> backup whenever you want.
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

Answer the App Store Connect privacy questionnaire as **Data Not Collected**.
This is truthful and provable from source: the app has no networking code (the
boundary scanner enforces this), and `PrivacyInfo.xcprivacy` declares no
tracking and no collected data types. Do not add any SDK or analytics that
would make this answer false.

## Category and age

- Primary category: **Medical** (or **Productivity** if a lighter regulatory
  posture is preferred; Medical is the honest fit).
- Age rating: complete the questionnaire truthfully; the app has no objectionable
  content, no user-generated content sharing, and no web access.

## Support and marketing URLs

A free static page satisfies the required support URL — a GitHub Pages site or
the repository README is sufficient at no cost. No privacy-policy URL is
strictly required when the label is Data Not Collected, but a one-paragraph
"this app collects nothing and never connects to a network" page is good
practice.

## Pricing

Free. No in-app purchases. No subscriptions.

## Screenshots

Required per device size. Capture on a real device or simulator, in airplane
mode, showing: first-run responsibility notice, three-tap capture, the recent
ledger with an outcome flip, the summary with the acceptance rate, and the DI
vault with a freshness badge. Use only fictional, non-identifying category
names.

## Remaining owner-only actions

These are external gates; none is performed by this repository.

- App icon art (see [`docs/app-icon.md`](app-icon.md)).
- Apple Developer Program enrollment and signing identity.
- Bundle identifier confirmation (`com.ayyitskevin.hippocrates` is set in the
  project).
- Marketing version 1.0 / build number (project sets `MARKETING_VERSION = 1.0`).
- On-device acceptance run ([`docs/acceptance-scripts.md`](acceptance-scripts.md)).
- TestFlight upload, then App Store submission.
- Publish the **Data Not Collected** privacy label.
