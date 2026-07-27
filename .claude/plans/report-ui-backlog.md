# Report / UI Backlog

Working list. Created 2026-07-23; last updated 2026-07-27. IDs stable; reference by number.

## ✅ Done + tested on DEV — PENDING PROD PROMOTION
Navigator rollout · My Data bookmark fix · Patient/Acquisition Deneb overflow · **#3** navigator selected-label · **#7** Acquisition x-axis title · **#5** Home Revenue → Dentist Hour + Revenue ribbon · **#6 Cancellations Rebooked** · **Patient Growth** · **Home card bar-height** fix.

**PROD promotion covers:** warehouse **V111 + V112 + V113**, **csx apply + model refresh** on prod, **PBI report re-publish/promote**, **Day Book app** dev→main PR (+ prod `REPORT_ID_DAY_BOOK` / `Access_Day_Book`).

## ✅ Done on DEV this pass (republish / deploy to see)
- **#1** KPI ribbon h=42 + navigator y=42 standardised (6 reports) — *republish*
- **#2** App nav font → Arial — *app deploy (auto)*
- **#4** Drill buttons → magnifier icon + un-inverted highlight (navy=available / grey=disabled) — *republish*
- **#8** Recalls by Status (`59450b97`) → active-patients filter (`Retention Outlook In Scope=1`) — *republish* (2-yr window still TODO ↓)
- **#10** Cancellations `-1` → "No reason recorded" — *deploy **V113** + Dim reload + refresh*
- **#12** "Open Courses With Appointment Value" measure added — *csx apply* (split wiring TODO ↓)
- **#15** Audit done — slicers consistent; only **Finance slicer (y=0)** off

## 🔶 Small remainders
- **#8 2-year window** on Recalls by Status — strict 2-yr window on `Due Date`. Best set in Desktop (filter pane → Due Date → **Relative date → is in the last 2 years**); the relative-date filter JSON is the one structure I won't risk authoring blind.
- **#12 split wiring** — after the csx apply, add the With/Without split to **My Data** (`b1b2b3`) + **Clinical** (`4c5ed0` + detail). Already shown on Home. (Hold until measure is live, to avoid a resolve error.)
- **#9 Patient Retention** detail + filter positioning — revisit after eyeballing #1/#4.
- **Finance slicer y=0** — align to the standard if wanted (Finance has no KPI ribbon).

## 🏗️ Bigger builds
- **#13 My Data** — Open Courses tab (course age + value, drill to patient list).
- **#16 Day Book — REVISIT** — full revamp per `.claude/plans/day-book-spec.md`.

## Parked
- **#14** Canvas height standardisation (per-report when we're in it).

## Closed
- Top-N "(Blank)" — verify · My Data Patients-by-Plan donut — fixed · Slicer "All"→"All X" — wontfix.
