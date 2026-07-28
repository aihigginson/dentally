# PROD issues found after the V104-V113 promotion (2026-07-27) — RESOLVED/triaged 07-28

**Headline: most of these were a transient partial/stale build.** A prod rerun (Orchestrate_Build)
cleared #1; #2/#4 had the same smell. Lesson: prod weirdness right after a build/promotion =
**suspect a partial build first — rerun + recheck before deep-diving.**

1. **Stephen Roberts = -73.75 hrs, wk 23 Feb.** ~~Investigate~~ **TRANSIENT — fixed by the rerun.**
   Post-rerun the Feb week reads +32.25 hrs (matches dev +32.5). Confirmed via prod token query.
   - **BUT a latent real bug remains (log, fix later):** 28 diary rows on prod have runaway
     `Break_Count` (max **72** breaks/day), 4 of which push `Available_Clinical_Mins` negative
     (all **Aug 2026**: 03-05 & 14). Root = Silver break calc fabricating breaks on real Dentally
     diary data. Aggregate `Worked_Hours` clamps to 0 (KPIs safe), but the **raw diary column stays
     negative** → any measure reading `Available_Clinical_Mins` directly shows junk when an Aug week
     is in view. Fix: correct the Silver break calc + clamp `Available_Clinical_Mins >= 0` in the
     diary load defensively.

2. **Rev/Dentist-Hour no target.** Likely same transient build. Left inconclusive (didn't confirm
   the target-table `Metric_Key` column name). Re-check in-report now prod is rebuilt.

3. **Drill-through inactive icon** — wants same magnifier shape as active with a red X through it.
   Still TODO (report change, follow-up to #4 drill button). Not a data issue.

4. **Relative dates look wrong.** **Real (minor) mechanism identified:** `Dim_Date.Relative_Day = 0`
   is anchored to the **build date** (was 27th; today 28th → everything relative off by a day, drifts
   daily until next rebuild). Fix = keep the nightly Orchestrate_Build running (already a known item).
   Not a code bug.

## Prod access (how, for next time)
Local `az login` has prod rights. Mint a warehouse token:
`az account get-access-token --resource https://database.windows.net --query accessToken -o tsv`
→ pyodbc against `emeh72n2ntdufpj4q665b2lzx4-eljzajgm5cpe5i64szgon7sej4.datawarehouse.fabric.microsoft.com`
DB `wh_dentally`, `attrs_before={1256: token-struct}`. Read-only, ~1h token. Prod F2 capacity
`analytically` (rg-analytically) may be **Paused** — resume via
`az resource invoke-action --resource-type Microsoft.Fabric/capacities -n analytically -g rg-analytically --action resume`.
