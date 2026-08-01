# Tenant-specific financial year — build plan

Let each practice set its FY start month (default April). NHS FY is ALWAYS Apr-Mar and is untouched.
Convention agreed 2026-08-01: **`Input.Targets.FY` stores the END/LABEL year**; label = `FY` + 2-digit(FY)
(no space, no century). Jan-Dec practices get a single-year FY (label just `FYyy`).

## Convention
- FY start month M (1-12) per tenant in `Input.Practice_Config.FY_Start_Month` (default 4).
- The FY **window** for label year Y: start = (M=1 ? DATEFROMPARTS(Y,1,1) : DATEFROMPARTS(Y-1,M,1)),
  end = DATEADD(YEAR,1,start)-1 day. So Apr-Mar FY27 = Apr-2026..Mar-2027; Jan-Dec FY27 = 2027 calendar.
- Label = 'FY' + RIGHT(Y,2). (Jan-Dec: single year; else the range's END year -- same string.)
- NHS FY (Apr-Mar) stays on `Dim_Date.Financial_Year` untouched.

## Data migration (repeatable; dev at cutover, PROD at go-live)
`Input.Targets` currently stores the START year. Shift each tenant's rows to the label/end year:
tenant 100: FY 2025->2026, 2026->2027 (i.e. FY += 1). Run in AppDB (source of truth); resyncs to WH.
Script: `Scripts/Migrate_Targets_To_Label_Year.py` (or a Migration). Idempotent guard needed (don't
double-increment) -- gate on a marker or run exactly once per env.

## Warehouse
1. **WH `Input.Practice_Config`** table + copy block in `Meta.usp_Sync_Input_From_AppDB` (AppDB->WH).
2. **`Dim_Date_Grouping` tenant-specific**: add `Tenant_ID`; the FY buckets (`FY24`,`FY25`,`FY27 (YTD)`)
   are generated PER TENANT from that tenant's FY_Start_Month + end-year labels. RLS by Tenant_ID.
   (It is already a many-per-date bridge off the unique Dim_Date, so +Tenant_ID adds no fan-out risk
   to Dim_Date itself.)
3. **`Gold.vw_Dim_Date`**: Dim_Date + per-tenant practice FY. Exposes `Financial_Year` = PRACTICE FY
   (label year), `Financial_Year_Name` = `FYyy`, AND keeps `NHS_Financial_Year` (= Dim_Date.Financial_Year,
   Apr-Mar). Per-date-per-tenant, RLS'd. Model repoints `List Date` here (test relationship: outcome A
   accept under RLS, else outcome B = practice FY lives on the RLS'd grouping and measures read it there).
4. **`Fact_Daily_Targets`**: explode the annual target across the PRACTICE FY working days (window from
   Practice_Config), keyed by label-year FY. NHS UDA/UOA targets keep Apr-Mar.
5. **Naming sweep**: `FY 2026-27` / `FY26/27` -> `FY27` everywhere (Dim_Date Financial_Year_Name, grouping
   labels, csx). NHS labels may stay explicit if needed.

## App
- `_fyLabel(y)` -> `'FY' + String(y).slice(2)` (stored year IS the label year).
- `/api/target-grid` (and targets save/read) return `fy_start_month`; the FY dropdown builds the right
  years/labels. The FY-box preview already computes end-year.
- Targets screen: the year list + copy-from use the new labels; values are label years.

## Measures (csx) -- outcome A (view accepted) preferred
- Practice measures using `'List Date'[Financial Year]` become practice-FY automatically (view swap).
- The ~4 NHS FY-YTD measures switch to `[NHS Financial Year]`.

## DECISION 2026-08-01: OUTCOME B (PBI won't accept the per-tenant view as List Date)
- `vw_Dim_Date` = BACK-END HELPER ONLY (grouping SP + Fact_Daily_Targets read it for the practice FY).
  MUST NOT become PBI.[List Date] -> ensure Meta.usp_Create_Gold_Views EXCLUDES it (or it supersedes).
- `List Date` stays = Dim_Date (Apr-Mar; NHS). The practice FY reaches the model ONLY via the RLS'd,
  tenant-specific `Dim_Date_Grouping` (Period slicer). Measures get the practice FY **from the selected
  Period** (grouping) -> drop the `'List Date'[Financial Year] = selectedFY` filter; sum Daily_Targets /
  actuals over the current date context (the period's dates). Relies on a Period being selected.

## Progress (this build)
- DONE + deployed: WH Input.Practice_Config + sync (V136); tenant 100 set to Jan (FY_Start_Month=1).
- DONE (committed, undeployed): Gold.vw_Dim_Date (math verified); tenant-specific Dim_Date_Grouping SP.
- TODO before the atomic manifest: (a) guard vw_Dim_Date out of Create_Gold_Views; (b) Dim_Date_Grouping
  Table.sql +Tenant_ID; (c) Fact_Daily_Targets on practice-FY working days (read vw_Dim_Date); (d) FYyy
  naming sweep; (e) app _fyLabel -> 'FY'+2-digit + /api/target-grid returns fy_start_month; (f) csx: drop
  [Financial Year] filter from the target/FY-YTD measures (period-based); (g) run FY+1 migration on dev;
  (h) one manifest -> deploy dev -> test; model: RLS on List Date Grouping by Tenant_ID (Desktop).

## Open / verify in Desktop
- RLS on `List Date Grouping` by Tenant_ID; the period-based target measures behave with a Period selected.
- Idempotency of the target migration (run once per env).
