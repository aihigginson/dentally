# Report / UI Backlog

Working list. Created 2026-07-23; last updated 2026-07-27. IDs stable; reference by number.

## Recently completed (removed from active list — all on dev, republish from Desktop)
Navigator rollout · My Data bookmark fix · Patient/Acquisition Deneb overflow · **#3** navigator selected-label size · **#7** Patient/Acquisition x-axis title · **#5** Home Revenue → Dentist Hour (value **+ target**) + added to Revenue ribbon + targets loaded + model refreshed.

## Open — report-side, I can do solo
- **#8 Recalls by Status** — active patients only; cap recall history at 2 years.
- **#10 Cancellations "blanks"** — *diagnosis resolved:* `Is_Cancelled` is correct (`Cancelled_At IS NOT NULL`). The blanks = **10,363 cancellations (32%) with NO reason recorded at source** (raw `Cancellation_Reason_ID` NULL) — real gaps, not a filter/backend bug. **Fix:** relabel the `fk_Cancellation_Reason = -1` bucket to "No reason recorded" (or exclude it) on the by-reason visual. *Minor:* 752 rows have a reason but `Cancelled_At` NULL → `Is_Cancelled=0`; optionally widen `Is_Cancelled` to include `fk_Cancellation_Reason <> -1`.
- **#12 Open Course Value** — split **With Appointment vs Without Appointment**.

## Open — needs a measure / backend + your csx apply
- **#6 Cancellation Rebook** (you: "Cancellations Rebooked") — metric **defined** as `cancellation_rebook` ("% of cancelled appts rebooked into a future slot", scheduling, higher-better) but **no DAX measure** and **no loaded target** (only `cancellation_frequency` + `short_notice_cancellation_rate` are in `Fact_Effective_Targets`). Build the measure set (X / X Target / X vs Target / X BG) in `PBI_Dentally.csx`, set + load the target, apply csx, then add to the Home **Scheduling** column + the Scheduling report.

## Open — needs your OK / pairing
- **#4 Detail drill button** — proposal: one right-aligned **"Details ▸"**, **navy when its drill target is active / grey when not** (fixes the inverted highlight), consistent on every report. Pairs with **#9 Patient Retention** detail + filter positioning. Awaiting go.

## Confirmed — likely no change
- **#11 Scheduling hours** — Diary Fill = scheduled hrs / worked hrs ✓; Chair Util = actual in-chair / worked hrs ✓; **no** forward Chair Util ✓. Clinical < Appointment hours is expected. Close unless a specific page is wrong.

## Bigger builds
- **#13 My Data** — Open Courses tab (course age + value, drill-through to patient list).
- **#16 Day Book — REVISIT** — straw man is wired into the dev app but needs a full revamp per **`.claude/plans/day-book-spec.md`**: unified task-flagged patient list + lens filters, hide no-issue patients, the DNA-risk + today's-appt data gaps, and a real Tracking measure.

## Parked / needs your input
- **#2** App menu font → match the PBI navigator font.
- **#1** KPI bar vs menu bar height/spacing (needs your eye).
- **#14** Canvas height standardisation (per-report when we're in it).
- **#15** Filter/slicer inconsistencies (awaiting your list of spots).

## Closed
- Top-N "(Blank)" — verify · My Data Patients-by-Plan donut — fixed · Slicer "All" → "All X" — wontfix (PBI limit).
