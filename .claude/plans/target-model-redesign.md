# Target Model Redesign — Practice + Owner-Curated Role

Status: **DESIGN — agreed in discussion 2026-07-14. Not yet built.**
Supersedes the per-practitioner targets spreadsheet and the ad-hoc filter/shape handling.
Companion to [[project_metric_layer_review]] / .claude/plans/metric-layer-review.md.

---

## 1. Why

Two problems, discovered while fixing the recall metrics and the Home-page filters:

1. **Filter behaviour is inconsistent.** Metrics carry ad-hoc flags (`Supports_Site`,
   `Supports_Practitioner`) and a zoo of measure shapes (`cur`, `currate`, `snap`, `rate`,
   `cum`…). Practitioner/Role/Active filters behave differently per metric; Role is "very broken".
2. **Ratios across heterogeneous cohorts are meaningless.** A general dentist targets ~50–60%
   Exam Ratio; a specialist ~10%. `ΣNum/ΣDen` gives ~40% — statistically true, useful to nobody,
   and comparable to no single target. Same for Chair Utilisation, Rev/Clinical Hour, Avg Plan Value.
3. The targets are loaded via a **clunky per-practitioner spreadsheet** that nobody enjoys.

The fault line is NOT "additive vs ratio". It is **"does the benchmark depend on the sub-population?"**
Volume metrics sum cleanly; efficiency ratios usually don't.

---

## 2. The keystone principle

> **No level's target is derived from another.** Practice, and each Role, each carry an
> **independent owner-set target**, and an actual is only ever compared to **its own level's**
> target. The naïve cross-cohort comparison never happens by construction.

- **Role target** = "what this cohort should do" (homogeneous by design — see Modified Role).
- **Practice target** = a **portfolio aspiration**, deliberately NOT the weighted average of the
  role targets. It measures **performance AND mix at once**. Example: £/plan is low → signal lights →
  owner fixes it either by lifting price across the board (performance) OR shifting the blend of work
  toward higher-value roles (mix). A Practice target that drifts as the mix changes is a **feature** —
  that drift is the mix signal the owner is acting on.
- (Bonus, later) the Practice gap decomposes: actual-blend vs on-target-mix = **performance**;
  on-target-mix vs Practice target = **mix**. "Is my £/plan problem my people or my case-mix?" — free.

This dissolves the heterogeneity problem: you never judge the all-dentist blend against a
general-dentist target — "All" lands on the **Practice** column, which the owner set with the mix
in mind.

---

## 3. Target dimensions

- **Practice** and **Modified Role** ONLY.
- **Drop Site** for now (Maple is single-site). Re-addable later as another level (Practice > Site > Role)
  if a multi-site practice needs it — design so it can slot in, don't build it.
- **No per-practitioner targets.** A practitioner is judged against **their role's** target.
  Sum-of-practitioners ≠ practice total anyway (unattributed/shared items), so targets are set
  **top-down per level, independently** — never derived bottom-up.

**Display grain can be finer than target grain.** Still show Exam Ratio / Chair Util per individual
practitioner (drill, spider); each is judged against their role's target. Fine to look at, coarse to target.

---

## 4. Modified Role — one curated column drives everything

`Dim_Practitioner.Custom_Role`:
- **Defaults** from the Dentally role (best-guess starting point).
- **Owner-editable** via a drag screen (see §7): create "Specialist Implantologist", drag a
  practitioner out of Dentist into it.
- **SCD-1 overwrite. Exactly ONE role per practitioner. No dates, no history.** A mis-drag +
  correction is just two overwrites with nothing to reconcile — effective-dating would turn every
  fat-finger into a data-cleaning ticket, to answer a question the owner already knows is caveated.
  Historical actuals re-bucket to the current role; that's accepted.

**Roles are data, not schema.** `DISTINCT Custom_Role` drives, with zero code:
- the target-grid **columns**,
- the app **Role filter** dropdown (switches from Dentally roles to `Custom_Role`),
- the **aggregation grouping** of actuals.

Add a role → a new (blank) target column appears, a new filter option appears, actuals start
aggregating under it. A role of one = an **opt-in** personal target (granularity on demand, never forced).

### Persistence (must survive the nightly rebuild)
`Dim_Practitioner` is rebuilt from Dentally each run, so the human edits CANNOT live in the dimension.
- **`Input.Practitioner_Role`** (override table, dateless current-state) = source of truth for the map.
- `Dim_Practitioner` load: `Custom_Role = COALESCE(Input override, Dentally default)`.

---

## 5. Data model summary

| Object | Shape | Notes |
|---|---|---|
| `Input.Practitioner_Role` | (Tenant, Practitioner_ID, Custom_Role) | owner-curated, SCD-1, one row/practitioner |
| `Dim_Practitioner.Custom_Role` | derived | COALESCE(override, Dentally default) |
| `Input.Targets` (re-shaped) | (Tenant, FY, Metric, Target_Level, Target_Value) | Target_Level ∈ {`Practice`} ∪ Custom_Roles. **Sparse** — blank = no benchmark = uncoloured |
| `Input.Metric_Variance` | (Tenant, Metric, Variance) | **per metric, NOT per cell, NOT per FY** — one tolerance band per metric (see §6) |
| Config.Metric_Definitions | keep | residual per-metric metadata: Aggregation class, Splits_By_Role, Range_Type, Format |

Residual per-metric metadata (everything else derives from the two curated tables):
- **Aggregation class**: `sum` (additive) | `ratio` (ΣNum/ΣDen) | `snapshot` (latest) | `min` (availability).
  (≈ today's `Target_Type`.)
- **Splits_By_Role**: does the metric split by role at all? Exam Ratio = yes; Email Rate / Days-Until-Free
  = no (practice-grain: Practice column only, ignores Role/Practitioner filter, greys). (≈ collapses
  `Supports_Practitioner`.)
- `Range_Type` (above/below/within) + `Format` — unchanged.

---

## 6. Aggregation & comparison rules (behaviour under the filters)

**Actual** = over the filter's members:
- ratio → `DIVIDE(ΣNum, ΣDen)`  |  additive → `Σvalue`  |  snapshot → latest  |  min → MIN.

**Target resolution** by filter:
- Practitioner selected → **their `Custom_Role`'s** column.
- Role selected → **that role's** column.
- None ("All") → **Practice** column.
- Practice-grain metric (`Splits_By_Role = no`) → always Practice column; ignore Practitioner/Role (grey).
- Resolved cell blank → **no verdict; show the value uncoloured.**

**RAG** = actual vs resolved target ± the metric's **variance band** (Range_Type-aware:
above/below = one-sided; within = symmetric band). Variance interpreted per format (pp for %, relative
% for count/£) — a stable **metric** property, hence per-metric not per-cell.

One measure template per Aggregation class, parameterised by metric key; grain decides whether it
follows or greys the Practitioner/Role filter. Replaces the current shape zoo.

---

## 7. Admin surface (retires the spreadsheet)

Two tabs, both **write back** to the Input tables:

**Tab A — Role assignment.** Columns = roles (Dentally defaults + custom); cards = practitioners;
drag between columns; "Add role" button. Writes `Input.Practitioner_Role`.

**Tab B — Target grid.** Rows = metrics; columns = `Practice | Role₁ | Role₂ | …` (derived from Tab A).
- **Current actual shown ABOVE each entry cell** (not to the left) so the owner sets the aspiration
  eyes-open against the current blend / mix gap.
- **Variance** = one column (one cell per metric row, spanning the level columns) — per-metric band.
- **FY selector**; when the chosen FY has no targets, a **"Copy from FY…" button with a source-year
  picker** seeds the grid from any already-populated year (owner then tweaks) — kills the blank-page
  problem. NOT a fixed FY‑1: owners typically fill the **current** year first to get going, then work
  **backwards**, so the source must be a chosen year, not "last year" (which is often still empty).
  Copies target VALUES; variance is per-metric (not FY-specific) so it carries over automatically.
- Writes `Input.Targets`.

### Write-back architecture (the real build)
The embed app is ~read-only today (bar managed-identity Xero token writes). This needs a **governed
write channel** from the app to `Input.Practitioner_Role` + `Input.Targets` (Fabric table writes via
managed identity / API). On rebuild, `Dim_Practitioner` + the target facts (Fact_Targets / Daily /
Effective) regenerate from the two Input tables.

---

## 8. What this replaces / simplifies

- Retires the per-practitioner targets spreadsheet (`Generate_Targets_Template` / `Load_Targets_From_Template`).
- Collapses `Supports_Site` + `Supports_Practitioner` + the measure-shape zoo into: **Aggregation class**
  + **Splits_By_Role** + the `Custom_Role`-driven aggregation.
- Role filter: Dentally roles → `Custom_Role`.
- Fixes Role ("very broken") and the practitioner-agnostic "No data" as *rules*, not per-metric patches.

---

## 9. Decisions locked (don't relitigate)

- Practice + Role only; **Site dropped** (re-addable later).
- **No per-practitioner targets** (judge vs role).
- **One role per practitioner, SCD-1, no history** — full stop.
- Practice heterogeneous-ratio target = **owner-set aspiration (option 2)**, independent of role
  targets; drift-with-mix is intended. (Options "blank" and "roll-up-the-verdict" rejected.)
- **Variance per metric** (not per cell/FY) — deliberate simplification, accepted.

## 10. Build order (when ready — NOT started)

1. `Input.Practitioner_Role` + `Dim_Practitioner.Custom_Role` (COALESCE).
2. Re-shape `Input.Targets` → (FY, Metric, Target_Level) + `Input.Metric_Variance` (per metric).
3. Regenerate target facts (Fact_Targets / Daily / Effective) from the new shape + role map.
4. Measures: aggregation grouped by `Custom_Role`; target resolution by filter; ~4 templates.
5. Admin screens (role drag + target grid, actual-above, FY copy) + the write-back channel.
6. Retire the spreadsheet; switch the Role filter to `Custom_Role`.
