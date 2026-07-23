# Report / UI Backlog

Working list — we tick these off together. Created 2026-07-23. IDs are stable; reference by number.

## Progress log — 2026-07-23 (autonomous session; commits are LOCAL, not pushed — eyeball in Desktop)
- **#3 DONE** — navigator "selected" label pinned to 8pt/regular across all 7 navigators (was inheriting a bigger size).
- **#5 DONE** — Home **Revenue** card now uses `Revenue Per Dentist Hour` (label auto → "Rev/Dentist Hr"); **Clinical** card keeps `Revenue Per Clinical Hour` → removes the duplication. Measure already exists in `PBI_Dentally.csx`; if the card shows blank, the model needs the current csx applied + refresh.
- **#7 DONE** — Patient/Acquisition "Week Ending Date" x-axis title hidden (visual `ecd102b2`).
- **#10 ROOT CAUSE (not yet fixed)** — `Gold.Fact_Appointments.fk_Cancellation_Reason = -1` on **224,758** non-cancelled rows (real reason IDs only on genuine cancellations). Any cancellation visual/measure **not filtered to `Is_Cancelled = 1`** pulls those in as spurious "(no reason)" rows — your symptom. **Fix:** add filter `Is_Cancelled = 1` (or exclude `fk_Cancellation_Reason = -1`) on the cancellation view(s). Left unfixed only because I want to pinpoint the exact visual with you; the filter add is low-risk. (`Fact_Appointments` has `Is_Cancelled, Is_DNA, Reason, Rebooked_Status, Cancelled_At`.)
- **#11 CHECKED — definitions are as desired.** `Diary Fill` = Appointment (scheduled) Hours / Worked Hours ✓; `Chair Utilisation` = actual capped in-chair hours / Worked Hours ✓. Only `Diary Fill` has a **Forward** variant; there is **no** forward Chair Utilisation ✓ (matches your requirement). "Clinical hours < appointment hours" is expected — Appointment Hours counts all booked appts; clinical/dentist chair time is a subset. If you still think a page is wrong, name it and I'll trace the exact measures.
- **#6 NEEDS A MEASURE (left for you)** — no `Rebooked Cancellations %` exists. Proposal: `DIVIDE(cancelled appts where Rebooked_Status = rebooked, all cancelled appts)`. Needs the `Rebooked_Status` value semantics confirmed + a csx add + your apply.
- **#4 DESIGN PROPOSAL (for your ok)** — one consistently-placed **"Details ▸"** button, right-aligned on the navigator/slicer row (top-right), styled as an app button: **navy fill + white text when its drill target is available (active), greyed when not** — which also fixes the inverted highlight (4b). Same position on every report. Say yes and I'll roll it out (pairs naturally with #9 Retention positioning).
- **Deferred (need you):** #1 (bar heights — subjective, needs your eye), #9 (do alongside #4), #12/#13 (report builds), #14/#15 (parked).


## Closed
- [x] **Top-N "(Blank)" series** — user reports fixed (verify on next pass through the Top-N charts).
- [x] **My Data "Patients by Plan" donut** — fixed.
- [~] **Descriptive slicer text** ("All" → "All Practitioners"/"All Sites") — WONTFIX, as good as PBI allows.

## App shell / chrome
1. **KPI bar vs menu (navigator) bar** — inconsistent heights, and the spacing between the two bars is off. Standardise heights + gap.
2. **App menu font → match the PBI navigator font** (we can't do it the other way round).
3. **Navigator "Selected" label** looks bigger/wrong vs the regular (unselected) label. Make the selected state match the regular font size.
4. **Detail drill-through button** —
   a. *Placement:* inconsistent across reports; make it consistent AND prominent. **NEEDS A DESIGN PROPOSAL from me.**
   b. *Highlight inverted:* currently bright when inactive and greyed when active — should be the reverse (bright/emphasised when active).

## Home report (+ corresponding reports)
5. **Revenue column:** change metric **"Revenue per Clinical Hour" → "Revenue per Dentist Hour"** (removes duplicated metric). Update the corresponding report(s) to match.
6. **Scheduling column:** add **"Rebooked Cancellations %"** metric. Update the corresponding report to match.

## Per-report fixes
7. **Patient / Acquisition:** remove the visible x-axis title **"Week Ending Date"**.
8. **Recalls by Status:** show **active patients only**; **cap recall history at 2 years**.
9. **Patient / Retention:** fix **Detail button + Filter positioning** (same issues seen elsewhere).
10. **Cancellations:** lots of spurious rows — **likely not filtering out non-cancellations**. Investigate the filter + fix.
11. **Scheduling — hours:** clinical hours booked consistently **< appointment hours** (more appointments than dentists). Verify **Diary Fill** and **Chair Utilisation** definitions. **Remove FORWARD Chair Utilisation** — chair util is based on actual patient-in-chair timings, so there is no forward-looking value.
12. **Open Course Value:** break down by **With Appointment vs Without Appointment**.

## My Data report
13. Add an **"Open Courses" tab** — age of course + value, with **drill-through to a patient list**.

## Parked / needs input
14. **Canvas height standardisation** (main pages 600 vs some detail/KPI 720) — minor; tackle per-report when we're already in that report.
15. **Filter/slicer inconsistencies across reports** — *user to enumerate the specific spots.*

## Next up
16. **Day Book report** — the 5-lens operational build. **Full spec: `.claude/plans/day-book-spec.md`** (ONE task-flagged patient list + lens filters; no-issue patients hidden; Tracking/BBYL as retrospective trends; house conventions: no header, KPI ribbon at y0, single-page overlaid bookmarks). First straw man was scrapped — built against none of this.
