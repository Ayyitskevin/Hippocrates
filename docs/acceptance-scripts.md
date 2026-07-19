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

## Recording results

For each script, record: date, device model, iOS version, pass/fail, and any
timing or notes. File the results wherever the owner keeps release evidence —
not in this public repository if they contain anything sensitive (they should
not, if only fictional data was used).
