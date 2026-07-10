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

3. **🔴 Default view compares 3 months actual vs a YTD-prorated target.** Default Period = "Last 3
   Months" (rolling), but `_Target FY Key` falls back to current FY and cumulative targets prorate by
   *elapsed FY working days*. So actual ≈ 3 months vs target ≈ elapsed-FY → every cumulative KPI looks
   badly behind on landing. (Verify, but the logic says broken on the default view.)

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

## 8. Next artifact to build
A **metric × dimension matrix**: each of the 34 metrics × { rolls-up-by-Site?, rolls-up-by-
Practitioner?, Period type = cumulative|rate|current-state, current behaviour under each dimension,
real-data validity, visualisation, verdict: keep|fix|re-scope|impossible|misleading|superseded }.
Assemble from `Config.Metric_Definitions` + the measure scripts, validate against real data, then the
metric-by-metric visualisation/validity discussion hangs off each row.

## Key file references
- Catalog: `Fabric/Config.Metric_Definitions.Data.sql` (34 metrics)
- Materialisation: `Fabric/Gold.usp_Load_Fact_Metric_Actuals.StoredProcedure.sql` (431 lines)
- Retarget: `Fabric/TabularEditor_MetricActuals.csx` (apply-map = the 27 pushed-down metrics)
- Value + KPI-wiring scripts: `Fabric/TabularEditor_{Revenue,Patients,Scheduling,Clinical,NHS,Finance}.csx`
- Period helpers: `Fabric/TabularEditor_Shared.csx` (`_Period Run Rate`, `_Target FY Key`, `_FY Period Key`, `_Is Practitioner Filtered`)
- Filter bar + apply logic: `Web/index.html` (filter bar ~432-468; apply ~1745-1761; dropdowns ~1697-1736)
- Practitioner dim: `Fabric/Gold.Dim_Practitioners.Table.sql` (has `Role`, `Active`)
