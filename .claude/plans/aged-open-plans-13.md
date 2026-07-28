# #13 Aged Open Plans — ready-to-execute plan (My Data + Clinical)

Prepared 2026-07-28 while unattended. NOT deployed (needs a model step + would touch the core
`Fact_Treatment_Plans` — didn't want to risk dev-wide Open Courses breakage unattended).

## Buckets (agreed)
0-15 / 15-30 / 30-60 / 60-90 / 90+ days, aged on `Start_Date` vs today. (First char sorts the
labels correctly, so no separate sort column needed.)

## The age dimension — pick ONE
**Option A (recommended): DAX calculated column via csx** — no warehouse change, no hash churn.
On the treatment-plan table in the model (the one exposing `Start Date` + `Private Treatment Value
Outstanding`), add:
```DAX
Course Age Bucket =
VAR d = DATEDIFF ( '_Treatment Plans'[Start Date], TODAY(), DAY )
RETURN SWITCH ( TRUE(),
    d < 15,  "0-15",
    d < 30,  "15-30",
    d < 60,  "30-60",
    d < 90,  "60-90",
             "90+" )
```
Evaluates at refresh (daily) — fine for an aged view. Add it in `PBI_Dentally.csx` next to the
other model objects, then the user applies csx + refresh. (TODAY() in a calc column = as-of-refresh.)

**Option B: warehouse column** — add `Course_Age_Days`/`Course_Age_Bucket` to
`Gold.Fact_Treatment_Plans` (CASE on `DATEDIFF(day, Start_Date, CAST(SYSUTCDATETIME() AS DATE))`),
regen views (`Meta.usp_Create_Gold_Views`), migration + manifest, reload. Downside: the age must go
in the upsert hash → every plan row updates every build (daily churn). Also still needs the column
added to the model. Only pick B if a calc column is unwanted.

## Report build (both My Data + Clinical)
Filter context = **open courses**: `Course_Status IN ('Open - No Appointment','In Progress')`
(confirm which — "aged open plans" most likely the leaky `Open - No Appointment`).
1. **New lens/tab** (bookmark, same overlay pattern as the Clinical trends just added): a
   `columnChart` — X = `Course Age Bucket`, Y = `Open Courses Value` (the outstanding private value).
   Optionally a second series/measure for count.
2. **Drill-through page** — a `tableEx`: Patient, Start Date, Age (days), Outstanding Value, filtered
   by the clicked bucket. Set the page as a drill-through target on `Course Age Bucket`.
3. Follow the report conventions (no header, KPI ribbon y=0, Arial). Build in git but DON'T publish
   until the model has the bucket column, else the visuals won't resolve.

## Sequence when back
csx (add calc column) → apply + refresh → build the lens + drill page → publish My Data + Clinical.
