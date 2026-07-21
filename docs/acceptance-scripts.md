# On-device acceptance scripts

These are the manual scripts the owner runs on a real iPhone before submission.
They close the human gates the automated hosted tests cannot: one-handed
timing, haptics, real airplane-mode behavior, the file importer, and a clean
restore on a fresh install. Simulator runs do not close these gates.

Run every script in **airplane mode** unless a step says otherwise. Use only
fictional, non-identifying data.

## A1 — Five-second one-handed capture (Milestone 2 exit gate)

1. Fresh install. Complete first-run: accept the responsibility notice, accept
   the starter categories.
2. Holding the phone in one hand, thumb only, record **ten** representative
   interventions: type → drug class → outcome.
3. Record the wall-clock time for each with a stopwatch (or a second person).

**Pass:** every entry completes in under five seconds; median well under.
Record the median and worst case. If any entry exceeds five seconds, note which
tap was slow.

## A2 — Outcome resolution and correction (I-013)

1. Record an intervention with outcome **Pending**.
2. In the Recent tab, swipe the row and mark it **Accepted**.
3. Open the row, change its drug class, save.
4. Swipe another row and **Remove** it; confirm.

**Pass:** the pending row resolves, the edit persists, the deletion confirms and
removes only that row. No free-text field appears anywhere.

## A3 — Manager summary and CSV (Milestone 3 exit gate)

1. With at least a dozen interventions across categories, open the Summary tab.
2. Confirm the acceptance rate shows with all four counts beside it and the
   denominator rule in text.
3. Tap **Share CSV** and save the file to Files. Open it in a spreadsheet app.

**Pass:** the numbers are correct; the CSV opens clean with no broken rows; a
category beginning with `=`, `+`, `-`, or `@` (create one to test) is not
executed as a formula. The owner would hand the summary to a manager unedited.

## A4 — DI de-identification gate (Milestone 4 exit gate)

1. Start a new DI record. In the background field, type a line containing a
   fake MRN (`MRN 12345678`), a date (`3/14/2026`), a room (`Room 412`), a
   phone number, and an age over 89 (`92-year-old`).
2. Save.

**Pass:** the review sheet blocks the save and lists each finding. The sheet
cannot be swiped away. Removing the text or marking each "Not an identifier"
is required to proceed. A clean record saves offline with no interstitial.

## A5 — Freshness and re-verification (Milestone 5 exit gate)

1. Create and answer a DI record with a short review interval.
2. Change the device date forward past the review date (leave airplane mode on;
   Settings → General → Date & Time).
3. Reopen the record from the vault.

**Pass:** the row shows the amber "Review due" (then red "Out of date" further
out) badge; opening interposes the staleness interstitial before the answer
every time; one-tap re-verify moves it back to green and appends to history.
Restore the real date afterward.

## A6 — Backup, wipe, restore (Milestone 7 exit gate)

1. With real (fictional) data present, open Categories → Backup → **Generate
   backup**, then **Share backup file** and save it to Files.
2. Delete the app. Reinstall.
3. On the fresh first-run screen, tap **Restore from a backup** and pick the
   saved file.

**Pass:** the importer opens; the file restores; the app lands in a populated
store with every intervention, DI record, and linked relationship intact.
Generating a fresh backup and comparing confirms the data survived. A backup
you deliberately corrupt (edit one byte) is refused with a clear message.

## A7 — Offline integrity

1. In airplane mode, exercise capture, summary export, DI save, and backup
   generation end to end.

**Pass:** every path works with no network. There is no spinner waiting on a
connection, no "offline" error, and no feature that requires connectivity.

## A8 — RXcalc draft safety, accessibility, and non-retention

Automation note: `HippocratesUITests/RXCalcCatalogAccessibilityTests.swift`
exercises only the catalog portion of step 3 at Accessibility 5, verifies one
semantic catalog button opens its calculator, runs Dynamic Type, hit-region,
clipped-text, and trait audits, and attaches screenshots. Automation
does not inspect those screenshots, cover complete detail-screen behavior or
VoiceOver/keyboard behavior, or run on physical hardware; it is supporting
evidence and does not pass or close A8.

1. Keep airplane mode on. Complete first run and open RXcalc. Confirm the catalog
   warning and every row show **Draft**, and that tools are grouped beneath
   **Body Size** and **Renal** category headers.
2. Search for `renal 2021`, `cockcroft-gault`, and `bmi bsa` with
   mixed case and extra whitespace. Confirm each query returns only the intended
   tool. Search `renal mosteller` and confirm there are no matches.
3. On a compact supported iPhone, set Text Size to the largest Accessibility
   size. Confirm every catalog title, complete summary, Draft badge, and category
   heading wraps without clipping or overlap, and that search and every row
   remain reachable by scrolling. Open each tool and confirm all inputs, actions,
   results, and safety/evidence sections remain reachable. Restore the normal
   text size afterward.
4. Turn on VoiceOver and open each tool. Confirm Draft status, summary,
   population, and required inputs are encountered before long-form limitations
   and evidence. Focus every numeric input and confirm the keyboard **Done**
   action is reachable and dismisses the keyboard without changing the value.
5. Cockcroft-Gault: age 50, male equation sex, 70 kg, serum creatinine 1.0
   mg/dL. Calculate and record **87.5 mL/min**.
6. 2021 CKD-EPI: age 90, female equation sex, serum creatinine 1.5 mg/dL.
   Calculate and record a displayed whole-number result of **33
   mL/min/1.73 m²**.
7. Body size: age 40, 170 cm, 70 kg. Calculate and record displayed **BMI 24.22**
   and **BSA 1.82 m²**. Confirm age 19 is rejected for this adult BMI surface.
8. With a locale that uses a comma decimal separator, enter `1,5` and confirm it
   is accepted as 1.5. Restore the normal locale afterward.
9. Calculate a result, then edit any input; the displayed result must disappear.
   Calculate again, change the associated unit, and confirm the numeric input is
   cleared rather than reinterpreted.
10. Enter values and calculate in all three tools. Force-quit and relaunch.

**Pass:** category/search behavior is exact; VoiceOver reaches safety and input
context before long-form evidence; catalog and detail text remains complete and
usable at the largest Accessibility size; the keyboard is dismissible; every
calculation works in airplane mode and matches the listed values;
review/formula/limitation context stays adjacent; invalidation and unit clearing
work; and relaunch retains no RXcalc inputs, results, favorites, or history.

## Recording results

For each script, record: date, device model, iOS version, pass/fail, and any
timing or notes. File the results wherever the owner keeps release evidence —
not in this public repository if they contain anything sensitive (they should
not, if only fictional data was used).
