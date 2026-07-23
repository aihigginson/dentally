# Report / UI Backlog

Working list — we tick these off together. Created 2026-07-23. IDs are stable; reference by number.

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
