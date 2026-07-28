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

## ✅ Unattended pass 2026-07-28
- **Clinical weekly trend charts** — added under Rev/Clinical-Hour, Avg Plan Value, Open Courses Value (columnChart by Week Commencing, bookmark-gated to the Revenue lens). Published to dev. Cross-*highlight* only (see note under Small remainders re: hard filter).
- **#8 2-year window** — DONE by user.
- **#12 split** — found ALREADY wired: both `b1b2b3` (My Data) + `4c5ed0` (Clinical) cards carry `Open Courses With/Without Appointment Value`. Depends on those csx measures being live — CONFIRM on test.

## 🔶 Small remainders
- **Clinical trends — hard filter** — currently default cross-highlight links the bars→trends. If you want a hard FILTER, it's one toggle in Desktop (Edit interactions) or I can add a `visualInteractions` block (no repo template, so I held off blind).
- **Drill icon (disabled)** — DEFERRED: a single actionButton can't overlay a red X only when drill is unavailable (native limit). Options for you: recolour the disabled magnifier RED, or supply a magnifier-with-X image. Needs your call.
- **#9 Patient Retention** detail + filter positioning — revisit after eyeballing #1/#4.
- **Finance slicer y=0** — align to the standard if wanted (Finance has no KPI ribbon).

## 🏗️ Bigger builds
- **#13 Aged Open Plans** — course-age buckets (0-15/15-30/30-60/60-90/90+) + value, drill to patient list. On **My Data AND Clinical** (user: "aged open plans report for My Data and Clinical").
- **#16 Day Book — REDIRECTED 2026-07-28** — short-term = **fill the forwards diary**: opening screen = Forwards Availability (manager view, Practitioner Full Name per row) → links to **Open Plans No Appointments**, **Recalls Not Sent**, **Recalls Not Booked**. Long term = direct Dentally API integration. See `.claude/plans/day-book-spec.md` REDIRECT section.

## Parked
- **#14** Canvas height standardisation (per-report when we're in it).

## Closed
- Top-N "(Blank)" — verify · My Data Patients-by-Plan donut — fixed · Slicer "All"→"All X" — wontfix.
