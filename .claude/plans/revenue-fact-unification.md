# Revenue Fact Unification — subsume Invoice Items + Plan Capitation into one `Fact_Revenue`

**Status:** IN PROGRESS on dev. Prereq done: capitation daily pro-rata (V147).
DONE (dev): `Fact_Revenue` built + Silver-sourced (GOLD_FACT), reconciles BYTE-IDENTICAL to the two
source facts (Invoice Δ£0.00 / 91,311 rows; Capitation Δ£0.00 / 2,659,041 rows); `_Revenue` view
regenerated; `Aggregate_Practitioner_Contribution` repointed → Fact_Revenue (production now incl
capitation, £7.31M→£9.87M); `GOLD_FACT_REVENUE` registered in Process_Config seed. Old facts kept
building (identical numbers) during transition — nothing double-counts.
REMAINING: (1) `Generate_Process_Dependencies.ps1` regen so the automated build orders Fact_Revenue
after its dims (currently built manually on dev). (2) `Fact_Metric_Actuals` repoint (5 invoice reads +
capitation; watch total-vs-capitation double-count) — deferred, numerically identical meanwhile.
(3) MODEL cutover: csx measures (Total Revenue/[Revenue]→SUM Amount, Private→Type=Invoice&NHS=0,
Category Bucket→Revenue_Category) + Desktop rewire (_Invoice Items→_Revenue, retire _Plan Capitation).
(4) Retire Fact_Invoice_Items + Fact_Plan_Capitation once nothing reads them.

## Why
Capitation is invoiced revenue — just billed outside Dentally (membership DD). Today it lives in a
separate fact with no treatment/invoice/category, so it's **excluded** from the revenue-by-category
Top-N chart and from any raw-invoice-based measure, and `Total Revenue` has to bolt it on with a
`+ [Plan Capitation Revenue]`. Unifying all revenue into one line-grain fact:
- puts capitation into category breakdowns as its own `"Plan Capitation"` category,
- makes it flow automatically into per-hour and **patient profitability** (correctly apportioned),
- collapses the invoice **header vs line** levels so they can't report different totals,
- kills the dual-source `Total Revenue` formula.

## Current state (verified on prod T100, 2026-08-10)
- **`Fact_Invoice_Items`** (GOLD_FACT, line grain, from Silver): `Total_Price`, `NHS_Charge`,
  `fk_Treatment`/`fk_Invoice`/keys. £7,337,581 / 91,604 items. Current `[Total Revenue]` = SUM of this.
- **`Fact_Plan_Capitation`** (GOLD_AGG, daily/member after V147): `Daily_Value`, keys, no treatment/invoice.
  Only GOLD_AGG because it reads two Gold **facts** — `Fact_Treatment_Plans` + `Fact_Treatment_Plan_Items`.
- **`Fact_Invoices`** (header grain): `Invoice_Amount`, `Discount_Amount`(=£0 everywhere), outstanding/
  due/paid. £7,337,357 / 49,747.
- **Reconciliation is already clean:** for **every** linked invoice, header `Invoice_Amount` = `SUM(lines)`
  (0 mismatches, £0 gap). The 230 header-only invoices are all **£0** (voided). The entire £224 header-vs-
  line gap is **3 orphan line items** (`fk_Invoice = −1`). Those are **transitory** — a working-day
  incremental pull can land an item before its invoice header; they re-link on the next pull. So keep
  them in revenue under a "(no invoice)" grouping; never drop.
- **Category Bucket / `Revenue (Top N)`** (csx): rank/slice a model measure `[Revenue]` (invoice-items
  based) by `'List Treatments'[Standard Treatment Category]` → capitation invisible.

## Target: `Fact_Revenue` (GOLD_FACT, built from Silver)
One row per **revenue unit** = an invoice line OR a capitation member-day.

Columns (draft):
| Column | Invoice line | Capitation line |
|---|---|---|
| `Revenue_Type` | `'Invoice'` | `'Capitation'` |
| `Revenue_Category` | line's Standard Treatment Category (sundry → `'Sundries'`; unmapped → `'Other'`) | `'Plan Capitation'` |
| `Amount` | `Total_Price` | daily pro-rata value (fee / days-in-month, capped at today) |
| `NHS_Charge` | line `NHS_Charge` | 0 |
| `fk_Invoice` | from item (−1 = transient orphan) | −1 (no Dentally invoice) |
| `fk_Patient / Practitioner / Practice_Site / Payment_Plan / Date` | resolved | resolved (practitioner = patient's dentist) |
| `fk_Treatment` | from item | −1 |
| `Is_Estimated_Plan` | 0 | capitation flag |
| detail: `Item_Name, Quantity, Item_Price` | from item | null |
| `pk_Revenue`, `Tenant_ID`, `DW_*` | | |

**Sourced entirely from Silver + Dims + Input → GOLD_FACT (no DAG inversion):**
- Invoice-line half ← `Silver.Invoice_Items` (same logic as today's `Fact_Invoice_Items` load).
- Capitation half ← re-source the two Gold-fact reads from Silver (confirmed feasible, all columns present):
  - `Fact_Treatment_Plans` → **`Silver.Treatment_Plans`** (Patient_ID, Start_Date, Completed,
    NHS_UDA_Value, Private_Treatment_Value, Id=plan bk).
  - `Fact_Treatment_Plan_Items` → **`Silver.Treatment_Plan_Items`** (Treatment_Plan_ID, Nomenclature,
    Charged).
  - Transforms: `Patient_ID → pk_Patient` via `Dim_Patients` (already joined for Active/attribution);
    `Start_Date → month` via `DATEFROMPARTS` (drop the `fk_Date_Start` surrogate lookup); EXISTS on
    `Treatment_Plan_ID` instead of the Gold surrogate. No information lost.
  - `Input.Plan_Capitation_Rate` unchanged. Membership/tenure/attribution/pro-rata/cap-at-today logic
    ported verbatim from V147 SP; **must produce byte-identical member-day output** (regression check).

**Retire:** `Fact_Invoice_Items` and `Fact_Plan_Capitation` (both subsumed). **Keep `Fact_Invoices`** for
AR only (outstanding / due / paid / is-outstanding). Its `Invoice_Amount` = the `Fact_Revenue` invoice
rollup by construction, so no second total.

**Load pattern:** DROP/CREATE full rebuild (capitation needs it; invoice-items incrementality is
sacrificed but ~2.75M rows rebuilds in ~1 min — acceptable). GOLD_FACT.

## Load classification & DAG
- Add `GOLD_FACT_REVENUE` (Gold.usp_Load_Fact_Revenue). Remove `GOLD_FACT_INVOICE_ITEMS` and
  `GOLD_AGG_PLAN_CAPITATION`. Regen `Generate_Process_Dependencies.ps1`.
- Repoint downstream consumers of the retired facts:
  - `Aggregate_Practitioner_Contribution` (reads Fact_Invoice_Items) → Fact_Revenue (Type=Invoice or all?).
  - `Fact_Metric_Actuals` (reads Fact_Invoice_Items + Fact_Plan_Capitation) → Fact_Revenue
    (total/nhs/private/plan_capitation metrics all derive from one fact now).

## Measures / model repoints (csx + model)
- Model table `_Invoice Items` → `_Revenue`; retire `_Plan Capitation`. Relationships (fk_Date, fk_Patient,
  fk_Practitioner, fk_Practice_Site, fk_Payment_Plan, fk_Treatment, fk_Invoice) rewired to `_Revenue`
  (manual, Desktop).
- `Total Revenue` = `SUM('_Revenue'[Amount])` (drop the `+ [Plan Capitation Revenue]`).
- `NHS Revenue` = `NHS Charge > 0` (self-excludes capitation, unchanged logic).
- `Private Revenue` = `Revenue_Type = 'Invoice' && NHS Charge = 0` (flag stops capitation counting as private).
- `[Revenue]` base measure (model-level, not in csx — **locate it**) → `SUM('_Revenue'[Amount])`.
- `Category Bucket` calc table → `DISTINCT('_Revenue'[Revenue Category])` (incl. "Plan Capitation");
  `Revenue (Top N)` ranks over `Revenue Category` (simpler than the treatment-dim TREATAS).
- Spider per-practitioner Total/Private/NHS → `_Revenue` (+ Type filter for Private).
- Per-hour (`Revenue Per Diary/Clinical Hour`) already via `[Total Revenue]` — verify still correct.
- `Plan Capitation Revenue` = `CALCULATE(SUM('_Revenue'[Amount]), Revenue_Type='Capitation')` (kept for the
  Home card / target; now derived from the unified fact).
- Retire `_Plan Capitation` refs; Discount/deposit measures unaffected (capitation Amount only).

## PBI views
- `Meta.usp_Create_Gold_Views` generates `_Revenue` from `Fact_Revenue`. Retire `_Invoice Items` +
  `_Plan Capitation` view generation.

## Reconciliation & regression tests
- `SUM(Fact_Revenue.Amount)` == old `SUM(Fact_Invoice_Items.Total_Price) + SUM(Fact_Plan_Capitation.Daily_Value)`
  (to the penny, modulo the capitation micro-rounding).
- Invoice rollup: `SUM(Amount) WHERE Type='Invoice' GROUP BY fk_Invoice` == `Fact_Invoices.Invoice_Amount`
  (except transient orphans).
- Capitation half of Fact_Revenue == current Fact_Plan_Capitation output (byte-identical member-days) —
  proves the Silver re-source didn't change the numbers.
- Category breakdown now includes "Plan Capitation"; NHS+Private+Capitation == Total.
- Add the above to `Test.Metric_Definition` / reconciles (T11 baseline).

## Deploy sequencing (minimise prod breakage)
1. Warehouse: deploy `Fact_Revenue` table + `usp_Load_Fact_Revenue`; wire Process_Config/dependencies;
   repoint `Aggregate_Practitioner_Contribution` + `Fact_Metric_Actuals`; rebuild; regen views (adds
   `_Revenue`, keeps old views until model cuts over).
2. Verify reconciliation on dev, then prod.
3. Model (Desktop + csx, user): add/repoint `_Revenue` table + relationships; run csx (measure repoints);
   refresh; retire `_Invoice Items` / `_Plan Capitation` tables + their views once nothing references them.
4. Drop the retired facts/views last, after the model no longer reads them.

## Decisions (resolved 2026-08-10)
1. **`[Revenue]`** is currently `SUM('_Invoice Items'[Total Price])` (invoice-only). Repoint to
   `SUM('_Revenue'[Amount])` so the Top-N/category chart includes capitation as the "Plan Capitation"
   category. (After unification `[Revenue]` and `[Total Revenue]` converge — both = SUM(Amount).)
2. **Sundries = their own category** → `Revenue_Category = 'Sundries'` (unmapped treatments still → `'Other'`).
3. **Contribution INCLUDES capitation** → `Aggregate_Practitioner_Contribution` sums all `Fact_Revenue`
   (no `Revenue_Type` filter); capitation counts toward each practitioner's production (attributed by the
   patient's dentist, `fk_Practitioner`).
4. **Keep invoice-line detail columns** (Item_Name / Quantity / Item_Price) on the unified fact (null for
   capitation) — cheap, preserves line-level drill. [default]
5. **Full rebuild** (DROP/CREATE) — capitation needs it and ~2.75M rows rebuilds in ~1 min; drop invoice-
   items incrementality for simplicity, revisit if volume grows. [default]

## Risks
- Model relationship rewiring is manual (Desktop) — the biggest hands-on step; brief window where revenue
  measures are transitional (no customers = OK).
- Capitation Silver re-source must reproduce the exact membership set — regression-gate it.
- `[Revenue]` and any other model-only measures not visible in git could reference the old table.
