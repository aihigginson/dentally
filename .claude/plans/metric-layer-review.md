# Metric Layer Review — working notes (session 2026-07-10)

Status: **discussion / design — NOT yet implementation.** Real Dentally data (Maple/T100) is now
live on prod, so the metric definitions (written in the mock-data era) need re-validating. This doc
captures the review so far. Next session picks up at "Open decisions" + builds the metric×dimension
matrix.

The driving asks from the user:
1. Review the metric metadata + Tabular Editor C# with a view to **refocusing on the KPIs the model
   is centred around**.
2. **Simplify** — move any processing possible back into the **warehouse** tables.
3. Find **additional metrics** that would improve product effectiveness.
4. Go **metric-by-metric**: for each, look at its **visualisation**, and call out any metric that is
   now **impossible or misleading** on real data.
5. **Test every metric against the app's filter model** (Period, Site, Role, Practitioner, Active).

---

## 1. How the metric system works today (architecture)

Three layers:

**Warehouse (Gold)**
- `Config.Metric_Definitions` — the catalog. 34 metrics. Cols: `Metric_Key`, `Display_Name`,
  `Section`, `Format_Type`, `Description`, `Long_Description`, `Supports_Site`,
  `Supports_Practitioner`, `Is_Active`, `Display_Order`, `Range_Type` (above|below|within),
  `Target_Type` (cumulative|rate|point_in_time).
- `Gold.Fact_Metric_Actuals` — the workhorse. One row per **(Tenant, fk_Date, fk_Practice_Site,
  fk_Practitioner, Metric)** with `Numerator` + `Denominator`. `fk_Practice_Site = -1` = all sites,
  `fk_Practitioner = -1` = all practitioners. Loaded by `Gold.usp_Load_Fact_Metric_Actuals`
  (DELETE + re-INSERT; SELECT INTO #temp + UNION ALL, Fabric-distributed-safe). Materialises ~27
  metrics via 5 shapes: cumulative, rate (num/den), snapshot, current-state value, current-state rate.
- `Gold.Fact_KPI_Snapshot` — weekly point-in-time stocks (active_patients, overdue_recalls,
  outstanding_invoices, open_courses_value).
- Aggregates: `Aggregate_Site_Patient_Practitioner_Daily`, `Aggregate_Site_Practitioner_Current`,
  `Aggregate_Site_Patient_Current`, `Aggregate_Practitioner_Contribution`.
- Targets: `Fact_Daily_Targets`, `Fact_Effective_Targets`, `Fact_Targets`.

**DAX (Tabular Editor C# scripts, `Fabric/TabularEditor_*.csx`)**
- Per-section value measures (bespoke) + generated **Target / vs-Target / BG** triples.
  Scripts: Revenue, Patients, Scheduling, Clinical, NHS, Finance, KPI_Snapshot, plus the Spider set
  (SpiderRevenue/Scheduling/Treatment/NHS, PractitionerSpider), PatientCohorts, AppointmentJourney,
  Formatting, Shared (period helpers).
- `TabularEditor_MetricActuals.csx` `MODE="apply"` **retargets ~27 value measures in place** onto
  `'_Metric Actuals'`, collapsing them to trivial SUM / DIVIDE / latest-snapshot over the one fact.
  `MODE="compare"` builds `<Metric> New` + `<Metric> Delta` for reconciliation against the bespoke
  "oracle" measures.

Assessment: the "move processing into the warehouse" instinct is **already ~80% done** via
`Fact_Metric_Actuals`. This review closes the remaining 20%, kills drift risk, fixes the filter
model, and fills metric gaps — not a rebuild.

---

## 2. Push-down opportunities (still live in DAX)

| Metric | Live DAX today | Push-down |
|---|---|---|
| **Net Patient Growth** (`Patients.csx` 278-293) | `FILTER(ALL('List Patients'), EDATE(Last Exam,24) BETWEEN …)` — per-patient scan every query; uses a *different* lapsed definition than materialised `lapsed_patients` | Materialise as `new_patients − lapsed_patients` (both already daily flows). Simplification + fixes card-vs-card disagreement. |
| **Revenue Per Dentist Hour** (`Revenue.csx` 223-235) | live `SUMMARIZE`/`FILTER` over daily aggregate, role ∈ {dentist, orthodontist} | Mirror the existing `revenue_per_clinical_hour` insert, dentist-only role filter (~15 lines). |
| **Recalls Overdue Not Sent, Patient Retention, Recall Effectiveness** (`Patients.csx` 331-363) | `COUNTROWS(FILTER(Aggregate_Site_Patient_Current…))` at query time | Pre-aggregate as `cur` num/den rows like `retention_outlook` / `email_details_rate` already are. |
| **DNA Revenue Lost** (`Revenue.csx` 237-254) | `dna_count × avg_appt_value` with `REMOVEFILTERS` | Materialise the two components daily. Lower priority (Home diagnostic). |
| **NHS UDA contract family** (`NHS.csx` 249-370) | heaviest in the model — pro-rata contract weeks, `USERELATIONSHIP`, FY-window `FILTER(ALL(...))`, `TODAY()` pace, `SUMX(COALESCE(...))` per claim | Pre-compute `Fact_NHS_Contract_Progress` at (Tenant, Site, Practitioner, FY, Week): cumulative delivered, cumulative pro-rata target, pace. Cards become MAX/lookup. Biggest perf win, most work. |

---

## 3. Simplification / drift risks

**3a. `open_courses` family computed twice — one copy is dead.**
`usp_Load_Fact_Metric_Actuals` materialises `open_courses`, `open_courses_value`,
`open_courses_without_appt` (SP lines 265-301), but `MetricActuals.csx` **excludes them from the
apply-map** (they read `Fact_Treatment_Plans` live in `Clinical.csx` for the 3-month recency band).
So the warehouse produces rows nothing reads → wasted compute + two definitions that can drift.
Decision: keep the SP rows only for the snapshot/trend history (document it) OR drop the inserts.

**3b. ~200 lines of identical builder DAX copy-pasted across 5 scripts.**
`tEff`, `tEff100`, `tEffAdd`, `vPct`, `vPp`, `vPctGrey`, `bgHigherEff`, `bgLowerEff`, `bgWithinPp`
etc. are verbatim duplicates in Revenue/Patients/Scheduling/Clinical/NHS. Since
`Config.Metric_Definitions` already carries `Range_Type` + `Format_Type` + `Target_Type`, the entire
Target/vs-Target/BG generation could be **one metadata-driven loop** over the catalog (or a shared
`TabularEditor_KpiBuilders` include, mirroring the existing `Shared.csx`). Highest-leverage
simplification: 5 hand-maintained scripts → 1 generator; a new metric then needs only a catalog row
+ a value measure.

**3c. Two-pass "define bespoke, then overwrite" is a footgun.**
Each retargeted value measure is written twice — bespoke live-DAX in the page script (the
reconciliation *oracle*), then overwritten by `apply`. Editing the page-script value measure has
**no effect** unless you also edit the metric map + reload the fact. Make it explicit (e.g. move
oracle defs to a labelled `_Oracle (reconciliation only)` folder, or comment-flag each).

---

## 4. Consistency / metadata hygiene

- **DAX metrics with no catalog row:** `nhs_udas`, `nhs_uoas`, `recall_compliance` (Recall
  Effectiveness), `patient_retention`, `dna_revenue_lost`. They bypass the catalog → no glossary
  entry, no centrally-governed Range_Type/colouring. Add them.
- **`deposit_ratio` metadata mismatch:** catalog says `Target_Type = point_in_time`, but it's
  computed as a period `rate` (MetricActuals shape `rate`, Revenue.csx uses `tEff100` + pp band).
  Fix catalog → `rate`.
- **Duplicate `Display_Order = 19`** (`net_patient_growth` & `outstanding_invoices`) + a couple of
  gaps. Minor; drives card order.

---

## 5. Additional metrics worth adding (from `project_kpi_design` intent, currently MISSING)

Verified absent in `Fabric/*.csx` (grep):
1. **Forward Book Value** — Tier-1 anxiety metric #3: £ value of appointments booked in the next 30
   days ("confirmed forward revenue"). Natural warehouse `cur`/snapshot metric.
2. **Reachable vs unreachable recall pipeline + revenue at risk** — have email/phone *rate* only, not
   "of X overdue, how many uncontactable + £ at risk (× avg appt value)". Data already in aggregates.
3. **Essential vs elective revenue split + elective pipeline value** — designed
   (`Config.Treatment_Category_Classification`, `Is_Elective`) but the table was **never created**
   (only the `Standard_*` mapping exists). Margin-growth signal; arguably the most owner-relevant add.
4. **Care Plan Estimated Revenue** (Option A) — active care-plan patients × plan fee × months. Still
   open whether the subscription fee is in the data.

---

## 6. THE FILTER MODEL — the big reframe (this is where next session starts)

### 6a. How the 5 filters actually wire (`Web/index.html`)
Report-level PBI filters via `setFilters` (NOT slicers), on these columns:

| Filter | Target column | Default |
|---|---|---|
| Period | `List Date Grouping[Date Grouping]` | **Last 3 Months** |
| Site | `List Practice Sites[Site Name]` | All sites |
| Role ("practitioner type") | `List Practitioners[Role]` (Dentist/Hygienist/Therapist only) | All roles |
| Practitioner | `List Practitioners[Full Name]` | All |
| Active only | **nothing on the report** — only narrows the practitioner *dropdown* via `/api/filters?active_only=1` | checked |

Filter apply logic: `Web/index.html` ~1745-1761. Dropdown population: ~1697-1736.

### 6b. The collapse: 5 filters → 3 dimensions
Per the user: **Role, Practitioner, and Active-only are all one dimension — Practitioner** (Role = a
roll-up of practitioners, individual = a leaf, Active-only = which leaves are offered). So there are
really **three dimensions: Period, Site, Practitioner.** The governing question per metric is just
two flags — **rolls up by Site? rolls up by Practitioner?** — which is exactly
`Supports_Site` / `Supports_Practitioner` in the catalog. Job = verify those flags against real data
+ enforce ONE consistent rule per case.

### 6c. Cross-cutting problems found (each affects many metrics)

1. **🔴 Role filter is ignored by every pushed-down metric — and returns the all-roles total.**
   `_Metric Actuals` measures resolve practitioner via
   `SELECTEDVALUE('List Practitioners'[pk Practitioner], -1)`. Role = "Dentist" filters the dim to
   *many* practitioners → `SELECTEDVALUE` returns the **−1 fallback** → measure reads the
   `fk_Practitioner = -1` (ALL practitioners, incl. hygienists/therapists) row. So Role selection
   changes nothing on Revenue, DNA, Chair Util, Acceptance, Avg Plan Value, Rev/Clinical Hour,
   Lapsed, New Patients, etc. Root cause: the **−1 pre-aggregation rows** that make single-select
   fast are incompatible with multi-select. This is the #1 item.

2. **🔴 Non-practitioner metrics behave 3 inconsistent ways under a practitioner selection:**
   - `active_patients`, `overdue_recalls` → `REMOVEFILTERS('List Practitioners')` → **stay correct** ✅
   - `retention_outlook`, `email/phone rate` → stored site/global only → **BLANK** on practitioner pick ❌
   - `recalls_overdue_not_sent`, `patient_retention` → aggregate has no practitioner relationship →
     **silently ignore** (correct number, but by accident) ⚠️
   - `net_patient_growth` → New Patients counts per-practitioner but lapsed half scans all patients →
     that practitioner's new minus the whole practice's lapsed → **actively wrong** ❌❌

3. ~~Default view compares 3 months actual vs a YTD-prorated target.~~ **RETRACTED (session 2, user
   tested):** the target WAS pro-rata correct when tested. The daily-target fact is summed over the
   SAME date context as the actual, and `_Period Run Rate` returns 1.0 for non-FY groupings, so
   "Last 3 Months" target = 3 months of daily targets vs 3 months of actual → reconciles. Not a bug.

4. **🟠 Current-state metrics ignore Period.** Snapshots + live current-state use
   `REMOVEFILTERS('List Date')`. Mathematically correct, but sliding Period and seeing them not move
   reads as broken → needs an "as of today" marker.

5. **🟠 `Supports_Site = 0` metrics are inconsistent + Role list is short.** Plan-grain metrics store
   `fk_Practice_Site = -1` only → materialised ones go **BLANK** on a site pick; live-DAX Clinical
   ones **ignore** site. Same page, opposite behaviour. Also the ⚠ "practice-level" prefix only fires
   on `ISFILTERED(pk Practitioner)` — it does **NOT** fire on a **Role** selection, so role-filtering
   a non-practitioner metric shows a wrong/blank number with **no warning**. And the Role dropdown
   offers only Dentist/Hygienist/Therapist — model roles include orthodontist/specialist → those
   practitioners are unreachable via Role.

### 6d. The two rules to ratify (turns the per-metric pass into classification, not adjudication)
- **Rule A — rolls up by practitioner (`Supports_Practitioner = 1`):** all three practitioner
  selections must aggregate correctly, **including Role multi-select**. Requires fixing the −1
  pre-aggregation issue (options: materialise a role grain; or have additive/rate measures `SUMX` the
  filtered practitioner leaf-rows and **drop the −1 rows** so DAX rolls up — rates sum num+den then
  divide, works for any filter set; snapshots need care as they're practitioner-agnostic).
- **Rule B — does NOT roll up by practitioner (`Supports_Practitioner = 0`):** practitioner dimension
  is **inert** — measure `REMOVEFILTERS` the practitioner dim so the figure stays the correct
  practice/site number, **and** the card carries a "practice-level" marker. No blanks, no wrong
  numbers.
- Mirror the same A/B logic onto **Site** via `Supports_Site`.

---

## 7. OPEN DECISIONS (pick up here next session)

1. **Ratify Rule B default:** when a metric doesn't roll up by the filtered dimension —
   **(a) stay correct + "practice-level" marker** (recommended), or **(b) go blank/greyed**?
2. **Superseded / dead-end metrics:** user to name the ones they already know are cut, so we don't
   waste the pass validating them. (User flagged "some metrics have been superseded, others are dead
   ends" — list still outstanding.)
3. **"Active only" semantics:** picker-only (today), or should it ever filter report data? (Only ever
   safe on current-state metrics; never historical.)
4. **Warehouse querying:** OK to run read-only warehouse queries (SP token via
   `Scripts/fabric_creds.local.ps1`) to ground the real-data validity calls (real `Role` values,
   plan/site attribution coverage, snapshot coverage) as we hit each metric.

## 7b. Session-2 decisions (2026-07-11)

Filter-rule decisions ratified:
- **Rule B (off-grain) = BLANK / greyed** — when a metric doesn't roll up by the filtered dimension,
  the card blanks/greys (not "stay correct + marker"). Implication: every measure needs a clean
  "dimension X is filtered and I don't support it -> BLANK" guard, INCLUDING the Role multi-select
  case; metrics that DO roll up still need the Role-multiselect −1 aggregation fixed so they don't
  silently blank.
- **"Active only" = data filter on CURRENT-STATE metrics only** — becomes a real report filter that
  bites only on current-state/forward measures; historical metrics stay unfiltered.
- **Read-only warehouse queries = approved.** BUT dev Fabric capacity is currently **paused**
  ("capacity not active") and prod is unreachable from the laptop (prod SP secret not local). So live
  grounding is deferred until dev is resumed OR the user runs prod queries. Query harness itself works
  (SP token + SqlClient; connects fine once capacity is up).

**Re-tiering is now an explicit output.** Real data has moved the tiers vs `project_kpi_design`.
Provisional calls from the user (off the top of head, to be confirmed in the methodical walk):
- **DNA rate / DNA revenue lost — DEMOTE.** Real DNAs are "not that much of an issue."
- **Net Patient Growth — ELEVATE.** Strongly negative on real data → this is a headline story.
- **Open courses — the one that matters is "without appointment" (esp. its VALUE).** Demote the
  plain `open_courses` count and `open_courses_value` (all-open); keep/elevate
  `open_courses_without_appt` + its value variant.
- **Recalls must be restricted to ACTIVE patients.** (retention_outlook, overdue_recalls,
  recalls_overdue_not_sent, recall_compliance — scope to active base.)
- **Lapsed patients — possibly its own tab under Marketing** (separate from the owner KPI pages).
- **Scheduling forwards:** drop `days_until_1hr_free`; keep `days_until_30min_free`. Add more focus on
  **immediate forward utilisation** (near-term booked/available capacity), not just "days until free".

Matrix gains a new column: **Tier / prominence** (Tier 1 headline / Tier 2 diagnostic / Tier 3
operational / cut / move-to-Marketing).

### Rule B mechanism — MASKS/OVERLAYS (to TRIAL first; user's idea)
Instead of blanking off-grain metrics measure-by-measure, overlay a mask/shape per page whose
visibility is bound to a measure, greying the cards that don't roll up by the filtered dimension.
Only ~2 visibility measures needed (support is fixed by card position):
- `_Practitioner filter active` = `IF( ISFILTERED('List Practitioners'[Role]) || ISFILTERED('List Practitioners'[Full Name]), 1, 0 )`
- `_Site filter active`         = `IF( ISFILTERED('List Practice Sites'[Site Name]), 1, 0 )`
Lay one mask over the non-practitioner cards (visible when practitioner filter active) and one over
the non-site cards (visible when site filter active). Keeps measures honest; better UX than a blank;
it's **.pbix Desktop layout work (user's job)**, out of the C#/measure layer.
- **Known risk:** pixel-perfect overlay alignment.
- **Does NOT solve Rule A** (Role multi-select on a metric that DOES roll up still returns the wrong
  −1 all-roles total behind the mask) — that still needs the warehouse/measure grain fix.
- **DECISION: do NOT implement per-metric measure-blanking until the mask trial is evaluated.**

### Revenue section — verdicts (session 2, user feedback)
1. **Total Revenue** — Tier 1, keep. Target proration confirmed correct. Still needs the Rule A
   Role-multiselect fix.
2. **NHS Revenue — REDEFINE (currently wrong).** Today = `SUM(Invoice Items)` where NHS_Charge>0.
   Should be **accepted NHS claims × a claims rate derived from the contract** (NHS work is paid by
   the NHS per UDA at the contract £/UDA rate, not via patient invoice lines). Source =
   `Fact_NHS_Claims` (accepted) × contract rate (`Fact_Contracts` / `Fact_NHS_Contract_Week`). Detail
   in the NHS section.
3. **Private Revenue — OPEN:** redefining NHS Revenue breaks `Total = NHS + Private` (Total = all
   invoice items; NHS was invoice-based). Need to decide how Total/Private recompose once NHS = claims
   × rate. Resolve during the NHS section.
4. **Revenue per Patient** — keep; denominator = **active patients** (confirmed). Ratio only
   meaningful at practice/site (patient count is practice-level) → set `Supports_Practitioner = 0`,
   mask at practitioner grain.
5. **Revenue per Clinical Hour** — Tier 1, keep. **Add Site support** AND ensure it works at
   Practitioner. Its Role-filter correctness is now load-bearing (it subsumes #6).
6. **Revenue per Dentist Hour — CUT (defunct).** Same as #5 with Practitioner Type = Dentist. (Makes
   the Rule A Role fix on #5 essential.)
7. **Deposit Ratio — REDEFINE % → £ value.** "Money received but work not done." Demote to a
   "by-the-way" figure, not a KPI. Rename toward `deposit_value`.
8. **Discounts — PARK (don't delete).** Blank on Maple, but other practices may discount. Keep,
   low/inactive prominence.
9. **Outstanding Invoices — keep but DEMOTE** (cash-on-delivery; exception-data area). Priority = make
   it **work under Practitioner filters** (Rule A fix; it already stores a practitioner grain).

### Patients section — verdicts (session 2, user feedback)
1. **Net Patient Growth — Tier 1, ELEVATE** (strongly negative = the headline story). Push down to
   `new_patients − lapsed_patients` (both already daily flows) so it's consistent + rolls up by
   site/practitioner. (Current live version's practitioner grain is wrong.)
2. **New Patients — Tier 2** (component of growth). Fix Role multi-select; consider enabling Site.
3. **Active Patients — keep** (denominator for per-patient + recalls). Practice-level → masked at
   practitioner.
4. **Retention Outlook — Tier 1** (best forward-looking retention number; pairs with the growth
   story). Restrict to ACTIVE patients. Patient/site grain → masked at practitioner.
5. **Recalls family** (`overdue_recalls`, `recalls_overdue_not_sent`, `recall_compliance`/Recall
   Effectiveness, `patient_retention`) — **restrict all to ACTIVE patients** (user call). Tier 2/3.
   Masked at practitioner. Catalog the uncatalogued ones (`recall_compliance`, `patient_retention`).
6. **Lapsed — `lapsed_patients` (total) KEEP on Patients as a KPI.** The three-way breakdown
   (`lapsed_deactivated` / `lapsed_calculated`) + corrective insight moves to the future **Marketing
   tab**. "A patient insight that is fixed by Marketing." Marketing tab does not exist yet.
7. **Email / Phone Details Rate — Tier 3** (reachability / data quality). Feed the proposed
   *reachable recall pipeline / revenue-at-risk* metric. Masked at practitioner.

**NEW SECTION FLAGGED: Marketing tab** (not built). First tenant = the lapsed-patient deep-dive +
corrective actions. Later home for acquisition-source / campaign attribution work
([[project_marketing_attribution]]).

### Clinical section — verdicts (session 2, user feedback)
1. **Treatment Acceptance Rate — LIKELY DEAD END; DEFER pending query.** Suspected uncomputable. Need
   to query real Maple: **can we identify REJECTED / declined plans** (not just un-started ones)? If
   yes, acceptance = accepted ÷ (accepted + rejected) may be salvageable; if no, **CUT**. Blocked on
   dev capacity.
2. **Open Courses (count, all open) — CUT / demote.**
3. **Open Courses Value (£, all open) — CUT / demote** (superseded by 4b).
4a. **Open Courses Without Appointment (count) — Tier 2, keep.**
4b. **Open Courses Without Appointment VALUE (£) — Tier 1, HOME card.** Not in the catalog today
    (lives as a live measure in `Clinical.csx`). **Catalog it** as `open_courses_without_appt_value`.
    Money committed, work not scheduled = owner anxiety number.
5. **Exam Ratio — Tier 3, keep pending verify** — does the appointment→exam classification survive
    real Dentally slot/treatment types (real `treatment_description` = slot-type, not clinical)?
6. **Average Plan Value — Tier 2, keep.**
- All Clinical metrics are plan-grain → `Supports_Site = 0` → **masked at site**; live-DAX open-course
  measures currently *ignore* site (masking fixes that consistently). Practitioner works (plan's own).

### Scheduling section — verdicts (session 2, user feedback)
1. **Chair Utilisation (historical, period)** — **Tier 2** (backward-looking capacity view).
2. **DNA Rate — Tier 2** (revised: sits at the SAME level as short-notice cancellations; keep both at
   Tier 2 for now — may be more significant for other practices). Uncatalogued **DNA Revenue Lost** —
   demote/park.
3. **Days Until Next 30-Min Free — Tier 2, keep.**
4. **Days Until Next 1-Hour Free — CUT** (user call).
5. **Book Before You Leave — Tier 2, keep — but REDEFINE.** BBYL *is* detectable. Current rule is
   suspected to require the next appointment to be booked **on the same day as the visit** — too
   narrow. Correct definition: at the point a patient leaves, do they **already have a future
   appointment on the books at all** (booked at any earlier time counts) — "in BBYL" until that next
   appointment occurs; 2+ appts already booked when leaving = BBYL. Use `Fact_Appointment_Journey`
   next-appointment pointers (V063) to compute. INVESTIGATE current rule + quantify corrected one.
6. **Cancellation Frequency — Tier 3.**
7. **Short Notice Cancellation Rate — Tier 2** (same level as DNA; the cost-bearing cancellation).
- Section pivots from a DNA/cancellation focus → a **forward-capacity focus**.

### NEW METRIC: Immediate Forward Utilisation — Tier 1, HOME (SPEC)
- **Horizon = next 7 days.** Present **both**: (a) **% fill** = booked appointment hours ÷ available
  worked hours over the forward 7-day window; (b) **£ Forward-Book Value** = confirmed forward revenue
  from appointments booked in the window (the missing Tier-1 "patient pipeline").
- **OPEN — data source:** can we use the **forward treatment_appointment** definitions for this, or
  should booked chair time come from **Fact_Appointments** (all booked slots, not just treatment-
  linked)? Forward CAPACITY (denominator) = `Fact_Practitioner_Diaries` (has ~14mo forward). Needs a
  real-data query once dev capacity is back to confirm forward appt + diary coverage.

### NEW VISUAL: 2-week diary HEAT MAP (operational)
Heat map of the **next 2 weeks** — chairs booked vs empty by day/practitioner. Operational (Tier 3),
distinct from the 7-day headline %.

### NEW FEATURE: Gap-filler function (operational, Tier 3)
"How you could fill the gaps" — surface **candidate open treatments / recalls / waiting-list patients**
against the empty forward slots. Turns the empty heat-map cells into an action list.

### Confirmations (session 2, user — no query needed)
- **Deposits** will be **sparse and transitory** on real data → confirms Deposit metric demote to a
  by-the-way £value, not a KPI.
- **Discounts blank** is **practice-specific** (Maple runs no discount schemes) → confirms PARK (keep
  for other practices, don't delete).
- **Role values are hard-coded in Dentally** (fixed enum) → low concern; still confirm the actual set
  present in Maple (does orthodontist/specialist appear → app dropdown only offers
  Dentist/Hygienist/Therapist).

### GROUNDING SWEEP (autonomous — user resuming dev capacity, away for hours)
User green-lit restarting dev capacity + autonomous investigation. Run one read-only sweep + write
findings back here. Targets:
1. **Roles** — distinct Role/count/active, T100 (confirm enum; orthodontist/specialist present?).
2. **Acceptance / rejected plans** — can a REJECTED/declined plan state be derived from
   `Fact_Treatment_Plans` (Start_Date / Completed / End_Date / any status field)? Decides
   acceptance_rate keep-vs-cut.
3. **Exam classification** — is `Exam_Count` populated + plausible on real slot/treatment types?
4. **BBYL** — read current rule (aggregate load SP); quantify current rate vs redefined
   ("future appt already on the books" via `Fact_Appointment_Journey`).
5. **Immediate forward utilisation feasibility** — forward non-cancelled appointments (next 7/14d)
   + hours from `Fact_Appointments`; forward worked hours from `Fact_Practitioner_Diaries`; forward
   expected value on treatment-appointments (for the £ side).
6. **Deposits / Discounts / Outstanding** — confirm sparse/blank/near-zero (cheap sums).
7. **Net patient growth / lapsed** — confirm flow data present + growth negative.
8. **NHS** — accepted claims (count/UDA) from `Fact_NHS_Claims` + contract £/UDA rate
   (`Fact_Contracts`/`Fact_NHS_Contract_Week`) → can we compute NHS Revenue = claims × rate? vs
   current invoice-based NHS revenue (preps the NHS-section redefinition + Private recomposition).

### GROUNDING SWEEP RESULTS (2026-07-12, dev warehouse, T100 Maple — real data)
Ordered by severity. Several are **warehouse correctness bugs**, not just metric re-scoping.

**A. 🔴🔴 NHS Revenue is showing £0 (critical).** Invoiced total = **£7,239,486**, but current NHS
Revenue (`SUM(Invoice_Items)` where `NHS_Charge>0`) = **£0** — `NHS_Charge` is never populated on
invoice items. So **Private Revenue = the entire £7.24M** (absorbs NHS work). Real NHS revenue via
**claims × rate = £624,621** (12,842 `completed` claims × £32.72). `Awarded_Dentist_Charge` /
`Dentist_Charge` are both £0 → the £ must come from `Awarded_UDA × contract UDA_Value`.
→ REDEFINE NHS Revenue = Σ(Awarded_UDA, completed claims) × contract rate. Decide Total/Private
recomposition (Total = private invoiced + NHS claim income?).
→ **Contracts stale:** only 2 loaded (2020-21, 2021-22; rate £32.72). **No current-year contract** →
contracts ingestion gap; need a current rate. Separate pipeline fix.

**B. 🔴🔴 Chair Utilisation understated ~2×.** "Block" appointments (NOT WORKING / Lunch / Annual
Leave / Bank Holiday — no patient, huge durations: NOT WORKING avg 435 min, Bank Holiday 647 min)
landing **on rostered days = 62,078 h**, vs total dentist+hygienist diary = ~122,342 h. Worked-hours
denominator doesn't subtract these → utilisation ~halved. **Fix:** subtract block-appt minutes on
rostered days from `Available_Clinical_Mins` in the aggregate/diary load. (User-flagged.)

**C. 🔴 Appointment-denominator pollution.** 17% of non-cancelled "appointments" (24,739 rows) are
diary blocks. Inflates DNA rate, exam ratio, cancellation, BBYL denominators. **Fix:** exclude blocks
(no-patient / reason-based) from appointment metrics.

**D. 🔴 Exam classification undercounts; Reason is free-text; HEX is dual-purpose.** Real appointment
`Reason` is free-text per practice (`HEX`, `Hex 20`, `3 12 Hyg`, `HYG 30 + AIRFLOW`, `Exam + Scale &
Polish`…). Current rule `LIKE '%Exam%'` = 35,653 and **misses all HEX (20,380)**; exam incl HEX =
56,033. **HEX = Exam + Hygiene combined → counts in BOTH exam and hygiene views** (user's unexpected
find; needs working into display). **Fix:** per-tenant `Config.Appointment_Reason_Classification`
mapping (Exam / Hygiene / Treatment / Emergency / New-Patient / Block; HEX → both).

**E. 🔴 Open Courses Without Appointment VALUE = £0 (fixable bug; it's the Tier-1 "eye-watering"
metric).** Raw `Private_Treatment_Value` = £8.6M (30,907 plans) landed fine, but
`Private_Treatment_Value_Outstanding` and `_Completed` are **£0 everywhere** (even on
`Has_Open_Item=True` plans). The outstanding/completed **split in `usp_Load_Fact_Treatment_Plans` is
broken on real data** — item open/charged classification doesn't match real Dentally item fields
(`Charged`/`Completed`/`Appear_On_Invoice`/`Status`/`NHS_Charge` on `Silver.Treatment_Plan_Items`).
Fixable; data is present. **Blocks the Tier-1 leaky-bucket £value + Open Courses Value.**

**F. Acceptance Rate — DEAD END confirmed.** `Accepted_At` NULL on all 68,371 plans; every plan has a
`Start_Date`; no reject state. Uncomputable as designed → **CUT** (or investigate whether `Accepted_At`
is a mapping gap before final cut — but as-is, nothing to compute).

**G. BBYL — redefined, REAL NUMBER = 66.7%.** Current same-day rule = **48.8%** (too narrow — only
counts next appts booked ON the visit day); "has any next appt" = **96%** (too broad). User's correct
definition ("a future appointment already on the books when they leave") = next appt's booking date ≤
this visit date = **66.7%** (69,817 / 104,741 completed). **Join key resolved:**
`Fact_Appointment_Journey.fk_Appointment_Next` = **`bk_Appointment_ID`** (the business key — NOT a pk;
confirmed 161,825 matches to both journey.bk and Fact_Appointments.bk; matches to either pk = 0).
Implement: `journey j LEFT JOIN Fact_Appointments nxt ON nxt.bk_Appointment_ID = j.fk_Appointment_Next
AND nxt.Tenant_ID = j.Tenant_ID`, BBYL = `nxt.fk_Date_Pending <= j.fk_Date_Start`. Ready to build.

**H. Net Patient Growth — strongly negative (Tier 1 justified).** Last 12mo: **379 new − 1,540 lapsed
= −1,161**. Active base **6,969** vs **20,784 inactive** (3× more lapsed than active).

**I. Recalls (active-scoped) — computable + meaningful.** Overdue active = **2,263**; overdue active
with no future appt = **1,885** (27% of the active base). Confirms scoping recalls to active.

**J. Contactability — healthy.** Active base: **94% have email, 99% have phone** (427 no-email, 39
no-phone of 6,969). email/phone metrics fine; feed the reachable-recall / revenue-at-risk metric.

**K. Low-value metrics confirmed.** Deposits **£87,037 / 534 rows** (~1.2% of revenue → by-the-way
£value). Discounts **£0** (→ park). Outstanding **£6,557** (0.09% → cash-on-delivery, heavy demote).

**L. Immediate forward utilisation — feasible.** Next 7d: **137 h booked / 171 h capacity ≈ 80% fill**
(mechanism works: `Fact_Appointments` forward ∩ `Fact_Practitioner_Diaries` forward). £ side needs a
value proxy (appts carry no price → avg-appt-value × forward count, or treatment linkage). Dev
forward-diary looked thin in the near term (data freshness) but horizon is long (diary → ~2029,
appts → ~2028).

**M. Roles (app filter mismatch).** Real roles: Dentist 15 (9 active), Hygienist 10 (6), + non-clinical
Administrator 13 / Receptionist 6 / Practice Manager 1 (all inactive). **No Therapist** — but the app
Role dropdown offers Dentist/Hygienist/**Therapist** (dead option). Non-clinical practitioner records
exist but are inactive → the "Active only" picker strips them (its real purpose). Fix the Role
dropdown to the roles actually present.

### NEW WAREHOUSE ACTIONS (from the sweep — warehouse layer, my side)
1. **Redefine NHS Revenue** = claims × contract rate (+ resolve Total/Private recomposition).
2. **Fix worked-hours** = subtract on-rostered-day block-appt minutes from `Available_Clinical_Mins`.
3. **Exclude diary blocks** from appointment-based metric denominators.
4. **Rebuild the appointment reason map** (per-tenant; HEX → exam+hygiene). DISCOVERY: a map already
   exists as **`Silver.Appointment_Reason_Map`** `(Reason_Text, Category, Sort_Key)` but it's a
   MOCK-ERA STUB — seeded with synthetic reasons ('Examination','Scale & Polish', etc.), so ALL real
   Maple reasons ('Exam','HEX','Hex 20','3 12 Hyg','NOT WORKING'…) fall through to 'Other'. It's also
   wrong-schema (Silver, not the `Config.*_Standard`+`Input.*_Map` pattern), 1:1 (can't do HEX dual),
   not per-tenant, and has no Block category. **Rebuild** as: `Config.Appointment_Reason_Standard`
   (canonical: Exam, Hygiene, Continuing Treatment, Emergency, Review, New Patient, **Block**, Other) +
   `Input.Appointment_Reason_Map` (`Tenant_ID, Reason_Text, Standard_Category`; **many rows per reason
   allowed** so HEX→{Exam,Hygiene}); retire `Silver.Appointment_Reason_Map`. Same map drives both
   classification AND the diary-block denominator filter (Block category). Seed from the real sweep
   taxonomy. OPEN: many-rows (recommended) vs boolean flags for the dual-category.
   Existing pattern refs: `Config.Cancellation_Reason_Standard` + `Input.Cancellation_Reason_Map`
   (mapping tooling: `Scripts/Generate_Mapping_Template.py`, `Scripts/Load_Mapping_From_Template.py`).
5. **Fix `Private_Treatment_Value_Outstanding`/`_Completed`** roll-up in `usp_Load_Fact_Treatment_Plans`.
6. **Cut acceptance_rate** (pending a quick Accepted_At mapping check).
7. **Contracts ingestion** — land current-year NHS contract (rate) — pipeline, not metric.

### ROOT-CAUSE + FIX DETAIL (autonomous session 2026-07-12)

**Bug E — Open Courses (Without Appt) Value = £0 → ROOT-CAUSED, one-field fix.**
`usp_Load_Fact_Treatment_Plans` computes the completed/outstanding split from **`tpi.Total_Price`**
(SP lines 97-100), but on real data `Total_Price` is **NULL on all 249,933 items** — the real value
field is **`tpi.Price`** (Σ = £8,445,161; matches plan-level Private_Treatment_Value £8.6M).
Recomputing outstanding with `Price` → **£1,338,575** (the real leaky-bucket value).
FIX: in the item aggregate CTE, change `ISNULL(tpi.Total_Price,0)` → `ISNULL(TRY_CAST(tpi.Price AS
DECIMAL(18,4)),0)` in BOTH `Private_Treatment_Value_Completed` (line 97-98) and
`Private_Treatment_Value_Outstanding` (line 99-100). (Also: item `Status` is blank on all rows — not
used by the Course_Status derivation, which keys off `Completed`, so no impact. `Quantity` also
unpopulated → use `Price` directly, not `Price*Quantity`.)

**Bug A — NHS Revenue redefinition, with real composition numbers.**
- Total invoiced (patient-paid) = **£7,239,486**. This INCLUDES NHS patient band charges.
- NHS patient charge (from completed claims `Patient_Charge`) = **£103,210** — the patient-paid slice
  sitting inside the £7.24M invoiced.
- NHS claim income (NHS-paid) = Σ(Awarded_UDA completed) × rate = **£624,621** — NOT invoiced, on top.
- `Awarded_Dentist_Charge`/`Dentist_Charge` both £0 → cannot use a charge field; must be UDA × rate.
- **Recommended recomposition (reconciles):**
  - Private Revenue = invoiced − NHS patient charge = £7,239,486 − £103,210 = **£7,136,276**
  - NHS Revenue = NHS claim income + NHS patient charge = £624,621 + £103,210 = **£727,831**
  - Total Revenue = Private + NHS = **£7,864,107** (= invoiced £7.24M + NHS-paid £625k)
  - NOTE: can't split invoiced items by NHS (NHS_Charge unpopulated on invoice items), but the NHS
    patient-charge slice IS knowable from claims — so the split above is computable.
  - **QUESTION FOR USER:** confirm this recomposition (esp. whether Total should include the NHS-paid
    £625k, i.e. cash the practice actually receives — recommended yes).
- Dim_Date has `Financial_Year` / `Financial_Year_Name` for per-FY UDA×rate (needed since the rate is
  per-contract-year; contracts currently stale — only 2020-22 loaded, rate £32.72).

### SYSTEMIC FINDING 🔴🔴 — the whole mapping layer is mock-seeded & blind to real values
The `Config.*_Standard` + `Input.*_Map` classification layer was seeded from synthetic data, so it
does not cover real Maple source values. Confirmed degradations:
- **Appointment reasons** → only coincidental matches (`Scale & Polish`→Hygiene works; `HEX`,
  `Hex 20`, `3 12 Hyg`, `Continuing Treatment`, `View` pass through unclassified). Exam undercounts
  (misses HEX), Hygiene/Treatment/Block all unreliable. [`Silver.Appointment_Reason_Map`]
- **Cancellation reasons** → **0 of 31,268 resolved** (`fk_Cancellation_Reason` unmapped for ALL
  cancelled appts) → **Short-Notice Cancellation Rate = 0%** (broken), cancellation-reason breakdown
  empty. [`Input.Cancellation_Reason_Map` / `Config.Cancellation_Reason_Standard`]
- **Acquisition source** → only **6,974 of 27,753 (25%) resolved** (~= active base) → 75% unmapped;
  marketing attribution sparse. [`Input.Acquisition_Source_Map`]
- (Payment plan map likely the same — unverified.)
→ **ACTION:** systematic RE-SEED of all Config/Input mapping tables from real per-tenant values, using
  the existing tooling (`Scripts/Generate_Mapping_Template.py` + `Load_Mapping_From_Template.py`).
  This is a prerequisite for: exam/hygiene/treatment split, Short-Notice rate, cancellation reasons,
  acquisition/marketing. One workstream, not per-metric. Rooted in the mock→real transition.

### More root-causes / section findings (autonomous session)
**Bug B — Chair Utilisation: block time is on BOTH sides (OPEN — finish with user tomorrow AM).**
Chair Util = appointment hours (numerator) ÷ worked hours (denominator). The block/dummy time
(NOT WORKING / Lunch / Annual Leave / Bank Holiday) is **neither appointment hours NOR worked hours —
it is a distinct non-working category**, and it currently contaminates BOTH sides:
 - Numerator: block "appointments" carry durations → they inflate appointment hours (they are NOT
   real appointment hours).
 - Denominator: the diary shows the practitioner available on those days → inflates worked hours
   (that time was NOT actually worked/available).
My earlier "subtract from Worked_Hours only" was HALF the fix. The correct principle (user, 2026-07-12):
**remove the block time symmetrically from both numerator and denominator** — real appointment hours
(excluding blocks) ÷ true available hours (diary minus block time). Worked example: 8h session, 3h
NOT-WORKING block, 4h real appts → 4 ÷ (8−3) = 80% (not 7/8 and not 4/8).
`Worked_Hours` today = `SUM(Available_Clinical_Mins)/60` from `#diary_agg` (SP lines 198-206);
`Appointment_Hours = SUM(Duration_Mins)/60` over the spine (`Is_Cancelled=0`, grouped by fk_Patient,
NO patient-present filter). **RESOLVED (autonomous, capacity back on 2026-07-13):**
- **Numerator IS polluted — heavily.** Of 188,647 h total Appointment_Hours in the aggregate,
  **144,179 h (76%) is no-patient block time**; only **44,468 h** is real patient appointments.
  (`NOT WORKING` alone = 97,728 h.) So today's numerator is nonsense, not just the denominator.
- **Cleanest fix — two filters, one per side:**
  - Numerator = appointment hours WHERE **`fk_Patient > 0`** (only patient-attended clinical time is
    "utilised") → 44,468 h.
  - Denominator = diary available − **explicit unavailable blocks by reason** (the reason-map `Block`
    category): NOT WORKING, Not working, Lunch, Annual Leave, Bank Holiday, Training Course, Meeting,
    Medical appointment. (NOT just `fk_Patient IS NULL`, which would also strip no-patient Exam
    *placeholders* that aren't "unavailable" time.) `'Other'` is ambiguous — 84% no-patient but 794
    real appts — so classify it in the reason-map, don't blanket-treat as Block.
- **Corrected utilisation ≈ 44,468 ÷ ~60,264 ≈ ~74%** (denominator = dentist+hyg diary 122,342 h −
  62,078 h on-rostered block; grains to be aligned in build). Sensible vs today's block-inflated value.
- Depends on the reason-map `Block` category (part of the mapping re-seed). Ready to build once the
  Block reason list is confirmed with the user. NO one-sided fix.

**NHS section — contract tracking broken on real data (pipeline gap).** Awarded UDA is steady
(~3,400-3,570/yr: FY22-23 3,362 · FY23-24 3,411 · FY24-25 3,557 · FY25-26 3,569 · FY26-27 977 partial),
but **contract targets exist ONLY for FY20-21 & FY21-22**. So NHS UDA Completion Rate, pace, Target,
and the £/UDA rate for NHS Revenue are **uncomputable for every year from FY22-23 on**. The whole NHS
contract page is blank/broken until current contracts are ingested. → PIPELINE: land current NHS
contracts (investigate why Fact_Contracts stops at 2022 — ingestion gap vs Dentally not exposing).

**NHS UOA = N/A for Maple.** 0 ortho claims of 12,958. Hide/skip UOA where a practice has no ortho
contract (it's a per-practice applicability flag, like NHS-vs-private).

**Finance/Xero — no data for T100.** `Fact_Finance` = 368 rows, **Tenant 11 only**. Maple hasn't
connected Xero, so EBITDA/Net Profit/margins are blank for the live customer. Metrics are sound
(validated on T11); it's a data-availability gap → Finance page needs the customer's Xero connected,
or hide until connected.

### DRAFT: Appointment-reason classification (real Maple, 63 distinct — for user approval)
Proposed mapping of the real reasons → standard categories. **Many-to-many** (HEX & New-Patient rows
map to 2 categories). Confirms the reason-map design. Approve/adjust, then load via
`Input.Appointment_Reason_Map` re-seed. (Counts are the ≥20-occurrence set; long tail <20 to bucket.)

- **Exam:** Exam · New Patient Exam* · Returning pt Exam · New Patient Exam 40*
- **Hygiene:** Scale & Polish · 30/20/40 Scale & Polish · Routine Hygiene · 3 12 Hyg · HYG 30/20 +
  AIRFLOW · Routine Hygiene + Airflow
- **Exam + Hygiene (DUAL):** HEX · Hex 20 · Hex 30 · Exam + Scale & Polish
- **Continuing Treatment:** Continuing Treatment · Crown recement/Fit/prep · RCT · XLA · Surgical XLA ·
  Impressions · Implant Placement · Bridge Recement · Denture Ease · Invisalign · Direct Access(?)
- **Emergency:** Emergency · Broken Tooth · Lost Filling · Lost Crown · Pain · Toothache · Chipped tooth
- **Review / Consult:** Review · New Patient Consultation* · Consult · Invisailgn Consulation · Implant
  Consult · mini Implant consult · New Patient Child Consultation*
- **New Patient (DUAL — cross-cut flag):** New Patient Exam{+Exam} · New Patient Consultation{+Review} ·
  New Patient Child Consultation{+Review} · New Patient Exam 40{+Exam}
- **Block (non-clinical — drives BOTH the denominator subtraction AND numerator exclusion):**
  NOT WORKING · Not working · Lunch · Annual Leave · Bank Holiday · Training Course · Meeting ·
  Medical appointment
- **Ambiguous → user call:** `Other` (4,981; 84% no-patient — Block or Other?) · `View` (2,683; has
  patients — a real slot type? Review?) · `Direct Access` (65)

Notes: New-Patient is a cross-cut like HEX (a "New Patient Exam" is New Patient AND Exam) → reinforces
the many-rows shape. The `Block` category does double duty (chair-util fix + cancellation/appt denom).
63 distinct reasons total; this is per-tenant (each practice's free-text differs).

### SQL FIXES — APPLIED 2026-07-13 (V064 + V065; awaiting user deploy + rebuild)
FIX 1 → `V064__tp_price_outstanding` (Fact_Treatment_Plans SP). FIX 2 + FIX 3 → `V065__chair_util_blocks`
(daily aggregate SP). Files edited + manifests written; NOT yet deployed. User to run:
`.\Scripts\Deploy.ps1 -Manifest Releases\V064__tp_price_outstanding.manifest -SkipTests` then V065, then
`Orchestrate_Build`. Drafts below kept for reference.

**FIX 1 — Bug E: Open-course outstanding value (FULLY CONFIRMED).**
File `Gold.usp_Load_Fact_Treatment_Plans.StoredProcedure.sql`, item aggregate CTE lines 97-100.
Real value field is `Price`, not `Total_Price` (NULL on real data). Swap both:
```
-- BEFORE (lines 97-100):
    SUM(CASE WHEN tpi.Completed = 1 AND ISNULL(tpi.NHS_Charge,0) = 0
             THEN ISNULL(tpi.Total_Price,0) ELSE 0 END)                          AS Private_Treatment_Value_Completed,
    SUM(CASE WHEN ISNULL(tpi.Completed,0) = 0 AND ISNULL(tpi.NHS_Charge,0) = 0
             THEN ISNULL(tpi.Total_Price,0) ELSE 0 END)                          AS Private_Treatment_Value_Outstanding
-- AFTER:
    SUM(CASE WHEN tpi.Completed = 1 AND ISNULL(tpi.NHS_Charge,0) = 0
             THEN ISNULL(TRY_CAST(tpi.Price AS DECIMAL(18,4)),0) ELSE 0 END)     AS Private_Treatment_Value_Completed,
    SUM(CASE WHEN ISNULL(tpi.Completed,0) = 0 AND ISNULL(tpi.NHS_Charge,0) = 0
             THEN ISNULL(TRY_CAST(tpi.Price AS DECIMAL(18,4)),0) ELSE 0 END)     AS Private_Treatment_Value_Outstanding
```
Effect: outstanding → £1.34M (from £0); lights up Open Courses Value + Without-Appt Value.

**FIX 2 — Bug B/C numerator + appointment-denominator pollution (CONFIRMED).**
File `Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily.StoredProcedure.sql`, spine WHERE (line 142).
No-patient block/placeholder rows must not count as appointments (they are 76% of Appointment_Hours):
```
-- BEFORE (line 142):
        WHERE apt.Is_Cancelled = 0
-- AFTER:
        WHERE apt.Is_Cancelled = 0 AND apt.fk_Patient > 0
```
Effect: removes blocks from Appointments, Appointment_Hours, DNA, BBYL, Exam denominators. NOTE: this
intentionally SHIFTS DNA rate / cancellation freq / exam ratio (they were inflated). Does NOT fix the
exam UNDERcount (HEX) — that needs the reason map, separate.

**FIX 3 — Bug B denominator: worked hours minus block time (DESIGN CONFIRMED; Block reason list PENDING
your approval — currently inline, swap for the reason-map `Block` category once re-seeded).**
Same file. Add a block-minutes aggregate BEFORE `#diary_agg` (after line 191), then subtract it:
```
        -- Unavailable/block time (entered as no-patient appts) must come OUT of worked hours.
        -- INTERIM reason list -> replace with the reason-map Block category after the mapping re-seed.
        DROP TABLE IF EXISTS #block_agg;
        SELECT apt.fk_Practitioner, apt.fk_Date_Start AS fk_Date, apt.Tenant_ID,
               SUM(ISNULL(apt.Duration_Mins,0)) AS Block_Mins
        INTO #block_agg
        FROM Gold.Fact_Appointments apt
        WHERE apt.Is_Cancelled = 0 AND (apt.fk_Patient IS NULL OR apt.fk_Patient <= 0)
          AND apt.Reason IN ('NOT WORKING','Not working','Lunch','Annual Leave','Bank Holiday',
                             'Training Course','Meeting','Medical appointment')
        GROUP BY apt.fk_Practitioner, apt.fk_Date_Start, apt.Tenant_ID;
```
Then replace the `#diary_agg` SELECT (lines 196-207) with the block-subtracted, floored version:
```
        SELECT
            d.fk_Practitioner,
            d.fk_Date_Day                                      AS fk_Date,
            d.Tenant_ID,
            CAST(CASE WHEN SUM(d.Available_Clinical_Mins) - ISNULL(bl.Block_Mins,0) < 0 THEN 0
                      ELSE SUM(d.Available_Clinical_Mins) - ISNULL(bl.Block_Mins,0) END
                 AS DECIMAL(10,2)) / 60.0                      AS Worked_Hours
        INTO #diary_agg
        FROM Gold.Fact_Practitioner_Diaries d
        LEFT JOIN #block_agg bl ON bl.fk_Practitioner = d.fk_Practitioner
                               AND bl.fk_Date        = d.fk_Date_Day
                               AND bl.Tenant_ID      = d.Tenant_ID
        GROUP BY d.fk_Practitioner, d.fk_Date_Day, d.Tenant_ID, bl.Block_Mins;
        DROP TABLE IF EXISTS #block_agg;   -- after #diary_agg is built
```
Effect (with FIX 2): chair utilisation ≈ real appts ÷ (diary − block) ≈ ~74% instead of block-inflated.

**Apply path:** each is a `DEPLOY` of the SP + a new manifest (e.g. `V064__tp_price_outstanding`,
`V065__chair_util_blocks`), then `Orchestrate_Build` to rebuild the aggregate/Fact_Treatment_Plans/
Fact_Metric_Actuals + model. FIX 1 is independent; FIX 2+3 ship together (both touch the aggregate).
Files are UTF-16 LE BOM — preserve encoding on edit.

### TARGET COVERAGE — Maple has NO business targets (found 2026-07-13)
Target machinery works (proven on T11) but is **empty for T100**:
- `Input.Targets`: 0 rows for T100 (99 rows T11 only). `Fact_Effective_Targets`: 0 for T100 (252 T11).
- `Fact_Daily_Targets` T100 = 261 rows but **`nhs_udas` only, STALE (fk_Date 7762-8126 ≈ 2020-21)**.
→ Every Tier-1 card shows an ACTUAL but no target / variance / RAG for the live customer.
- Target-calc (DAX) exists for 4 of the 6 Tier-1: total_revenue (tDaily), net_patient_growth
  (tEffRunRate), revenue_per_clinical_hour (tEff), retention_outlook (tEff100). The 2 NEW ones
  (immediate_forward_utilisation, open_courses_without_appt_value) have neither metric nor target.
→ ACTIONS: (a) build the 2 new metrics + their target keys; (b) **enter Maple business targets into
  `Input.Targets`** (per-practice onboarding step; use the T11 Excel template/prefill); (c) NHS target
  needs current contracts (see contract-ingestion gap). Tier-1 RAG is blank until (b).

### PIPELINE GAP: Waiting-list MEMBERS not landed
We ingest waiting-list NAMES but **not the people on them**. Needs landing (new ingestion) to power
the gap-filler ("these waiting-list patients could fill these gaps"). Separate ingestion workstream,
not a metric. See [[project_entity_design_remaining]] (Waiting Lists: NHS / Private New Patient).

## 8. THE METRIC × DIMENSION MATRIX (built, session 2026-07-12)
Legend — **Site/Prac** = rolls up by that dimension (Y/N; N ⇒ Rule-B mask). **Per** =
C(cumulative)/R(rate)/P(point-in-time)/Cur(current-state). **Data** = real-Maple status.
**Tier** post-review.

| Metric | Sec | Site | Prac | Per | Data (real Maple) | Tier | Verdict / fix |
|---|---|---|---|---|---|---|---|
| total_revenue | Rev | Y | Y | C | OK £7.24M | 1 | keep; fix Role-multiselect |
| nhs_revenue | Rev | Y | Y | C | 🔴 £0 (NHS_Charge unpop) | 1 | REDEFINE = claims×rate (£728k incl patient charge) |
| private_revenue | Rev | Y | Y | C | ⚠ overstated (absorbs NHS) | 1 | recompose = invoiced − NHS patient charge (£7.14M) |
| revenue_per_patient | Rev | Y | N | R | OK | 2 | denom=active pts; mask at prac |
| revenue_per_clinical_hour | Rev | **Y(add)** | Y | R | 🔴 understated ~2× | 1 | fix worked-hours; ADD site |
| revenue_per_dentist_hour | Rev | — | — | R | — | CUT | = rev/clinical hr + Role=Dentist |
| deposit_ratio→deposit_value | Rev | Y | Y | £ | sparse £87k | by-the-way | REDEFINE %→£; not a KPI |
| discounts | Rev | Y | Y | R | £0 (none) | park | keep for other practices |
| outstanding_invoices | Rev | Y | Y | P | tiny £6.5k | demote | fix Role filter |
| net_patient_growth | Pat | Y | Y | C | 🔴 −1,161/yr | 1 | ELEVATE; push down = new−lapsed |
| new_patients | Pat | N(→Y?) | Y | C | OK 379/12mo | 2 | fix Role; maybe enable site |
| active_patients | Pat | Y | N | P | OK 6,969 | keep | denominator; mask at prac |
| retention_outlook | Pat | Y | N | Cur | OK | 1 | scope ACTIVE; mask at prac |
| overdue_recalls | Pat | Y | N | P | OK 2,263 active | 2 | scope ACTIVE |
| recalls_overdue_not_sent | Pat | Y | N | Cur | OK | 2/3 | scope ACTIVE |
| recall_compliance / patient_retention | Pat | Y | N | Cur | OK (uncatalogued) | 2/3 | catalog + scope ACTIVE |
| lapsed_patients | Pat | Y | Y | C | OK 1,540/12mo | 2 | keep on Patients (total) |
| lapsed_deactivated / lapsed_calculated | Pat | Y | Y | C | OK | Mktg | move breakdown to Marketing tab |
| email_details_rate | Pat | Y | N | Cur | OK 94% | 3 | mask at prac; feed reachable-recall |
| phone_details_rate | Pat | Y | N | Cur | OK 99% | 3 | mask at prac |
| acceptance_rate | Clin | N | Y | R | 🔴 DEAD (Accepted_At null) | CUT | uncomputable |
| open_courses (count) | Clin | N | Y | Cur | OK 879 open (207 IP + 672 no-appt) | demote | superseded |
| open_courses_value (all) | Clin | N | Y | Cur | 🔴 £0→fix(Price) | demote | superseded by w/o-appt value |
| open_courses_without_appt (count) | Clin | N | Y | Cur | OK 672 | 2 | keep |
| **open_courses_without_appt_value** | Clin | N | Y | Cur | 🔴 £0→**£1.34M via Price** | **1** | CATALOG it; Home card; fix Price |
| exam_ratio | Clin | N | Y | R | 🔴 denom polluted + HEX miss | 3 | needs reason-map + block filter |
| avg_plan_value | Clin | N | Y | R | OK (via Price) | 2 | keep |
| chair_utilisation | Sch | N(→Y?) | Y | R | 🔴 block time on BOTH sides | 2 | OPEN: symmetric block exclusion (num & denom) — finish w/ user tomorrow |
| dna_rate | Sch | N | Y | R | OK ~2% | 2 | block filter denom |
| days_until_30min_free | Sch | Y | Y | Cur | OK | 2 | keep |
| days_until_1hr_free | Sch | — | — | Cur | — | CUT | user call |
| book_before_you_leave | Sch | N | Y | R | ⚠ 48.8% (narrow rule) | 2 | REDEFINE via journey next-ptr |
| cancellation_frequency | Sch | N | Y | R | OK ~18% | 3 | block filter denom |
| short_notice_cancellation_rate | Sch | N | Y | R | 🔴 0% (cancel map dead) | 2 | needs cancel-reason re-seed |
| **immediate_forward_utilisation** (%+£) | Sch | Y | Y | Cur | feasible (80% fill 7d) | **1** | NEW; Home; £ needs value proxy |
| nhs_uda_completion_rate | NHS | Y | Y | R | 🔴 no recent target | 1(NHS) | blocked on contract ingestion |
| nhs_udas | NHS | Y | Y | C | OK delivery | 2 | target blocked |
| nhs_uoas | NHS | Y | Y | C | N/A (0 ortho) | hide | per-practice applicability |
| EBITDA/Net Profit/margins | Fin | Y | N | C | no T100 data | — | needs Xero connected |

## 9. CONSOLIDATED QUESTIONS FOR THE USER (accumulated this session)
1. **NHS Total/Private recomposition** — confirm: Private = invoiced − NHS patient charge (£7.14M);
   NHS = claim income + patient charge (£728k); Total = £7.86M (includes the £625k NHS-paid). OK?
2. **Acceptance rate** — `Accepted_At` is NULL on ALL plans. Is that a Dentally-doesn't-expose fact,
   or a transform MAPPING gap worth fixing before we hard-cut? (As-is → CUT.)
3. **HEX display** — HEX = exam+hygiene. Count in BOTH exam & hygiene, or show a separate "combined"
   line? (drives the reason-map many-to-many shape.)
4. **Reason map shape** — many-rows (recommended) vs boolean flags for dual-category reasons.
5. **Mapping-layer re-seed** — OK to re-seed ALL Config/Input maps (appointment reason, cancellation
   reason, acquisition source, payment plan) from real per-tenant values via the existing tooling?
   (Prerequisite for exam/hygiene split, short-notice rate, cancellation & marketing breakdowns.)
6. **NHS contracts ingestion** — Fact_Contracts stops at FY21-22. Land current contracts (needed for
   completion rate + NHS £/UDA rate). Is this a known ingestion gap or does Dentally not expose them?
7. **Chair Utilisation / Rev-per-Clinical-Hour site support** — both are `Supports_Site=0` today but
   arguably need per-site for multi-site owners. Add site grain? (Maple is single-site so low urgency.)
8. **Immediate forward utilisation £** — appointments carry no price; use avg-appt-value × forward
   count (proxy) or wait for treatment-appointment expected value? (proxy is buildable now.)
9. **"Active only" as a data filter on current-state metrics** — confirm which metrics it should bite
   (availability/forward) vs never (all historical).

## 10. Recommended build order (once questions resolved)
1. **Mapping-layer re-seed** (systemic; unblocks exam/hygiene, short-notice, cancellation, marketing).
2. **Quick warehouse bug fixes:** Price→outstanding (Bug E, 1 line); worked-hours block subtraction
   (Bug B); NHS Revenue redefine + Private recompose (Bug A); block-filter appointment denominators.
3. **Metric re-scope + tiers** in `Config.Metric_Definitions` (catalog the uncatalogued; cut
   acceptance/dentist-hour/1hr-free; add open_courses_without_appt_value + immediate_utilisation).
4. **Rule-A fix** (Role multi-select on materialised metrics) + **Rule-B masks** (Desktop trial).
5. **New builds:** immediate forward utilisation, Marketing/lapsed tab, 2-week heat map, gap-filler,
   waiting-list ingestion, NHS contracts ingestion.
6. **DAX simplification** (one metadata-driven builder) — last, once the catalog is settled.

## Key file references
- Catalog: `Fabric/Config.Metric_Definitions.Data.sql` (34 metrics)
- Materialisation: `Fabric/Gold.usp_Load_Fact_Metric_Actuals.StoredProcedure.sql` (431 lines)
- Retarget: `Fabric/TabularEditor_MetricActuals.csx` (apply-map = the 27 pushed-down metrics)
- Value + KPI-wiring scripts: `Fabric/TabularEditor_{Revenue,Patients,Scheduling,Clinical,NHS,Finance}.csx`
- Period helpers: `Fabric/TabularEditor_Shared.csx` (`_Period Run Rate`, `_Target FY Key`, `_FY Period Key`, `_Is Practitioner Filtered`)
- Filter bar + apply logic: `Web/index.html` (filter bar ~432-468; apply ~1745-1761; dropdowns ~1697-1736)
- Practitioner dim: `Fabric/Gold.Dim_Practitioners.Table.sql` (has `Role`, `Active`)
