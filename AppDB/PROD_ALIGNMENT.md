# Prod vs dev — what is aligned, what is deliberately not, and what is left

Measured 30 Oct 2026 by diffing the two warehouses and the two AppDBs directly, not by reading
commit history. Scripts used are throwaway but the method is worth repeating: **compare the
databases, not the repo**.

---

## Aligned

| | |
|---|---|
| `Gold`, `Silver`, `Bronze`, `Config`, `Security`, `Meta`, `Audit`, `Billing`, `Sales` | **0 column gaps** |
| `Input`, `Input_Stage` (both AppDB and warehouse) | **0 column gaps** |
| Stored procedures and functions | **0 missing on prod** |
| Semantic model `PBI Dentally` | **56 tables each, 0 differences either way** |

Closed during the targets release: 28 column gaps, two migrations that existed nowhere
(`Target_Level_Columns`, V154), `Rolls_Up` (V155), `fk_Practice_Site` on the treatment-plan fact
(V156), and six stored procedures.

---

## Deliberately different — do not "fix" these

### `Stage.*` is environment-shaped, and prod has MORE

Prod lands the real Dentally API; dev's generator writes the subset it needs. So prod carries
`address_line_1..3`, `bad_debtor`, `preferred_phone`, `triage`, `not_measured_on_udas` and a long
tail of others that dev has never had. Aligning Stage **downward** would delete real ingested
fields; aligning it **upward** means teaching the generator to write them, which is only worth doing
for a column something reads.

The one exception is `Stage.Appointments.site_id`, which dev has and prod does not. That arrives
with the **ingest notebook**, whose field list is promoted through the Fabric pipeline, not deployed
as SQL.

### Eleven views differ by a provenance comment only

`Audit.v_24Hr_Processes`, `v_48Hr_Processes`, `v_Custom_Messages`, `v_Daily_Messages`,
`v_Daily_Processes`, `v_Debug_Messages`, `v_Error_Messages`, `v_Info_Messages`,
`v_Process_Dependencies`, `v_Warn_Messages` and `Gold.vw_Fact_Payments`.

Every one differs by exactly the same thing: prod's copy carries a Fabric-generated header,

    -- Auto Generated (Do not modify) 35B3F65041...

plus a trailing newline. **The bodies are identical.** Prod's were created through the deployment
pipeline, which stamps that line; dev's were deployed directly. Redeploying eleven live views to
remove a comment is risk with no gain. Expect them in every future diff and ignore them.

### Two objects exist only on prod

* `Gold.usp_Load_Fact_Daily_Targets` — the retired loader. Held on purpose until the new chain has
  been watched for a few days; it is the only fallback left.
* `Audit.usp_Run_Single_Job` — prod-side operational tooling, not in the repo.

---

## The drift is not one-directional

Two procedures had **prod ahead of dev**, and deploying "dev to prod" would have been a regression:

* `Gold.usp_Load_Dim_Treatment_Plans` — prod cast the NHS UDA columns `DECIMAL(18,4)`; dev's
  deployed copy still had `DECIMAL(10,2)`. The repo matches **prod**. Dev was redeployed from the
  repo; pushing dev's copy to prod would have narrowed live NHS values.
* `Gold.usp_Load_Dim_Patients` — comment only, prod's better. Dev redeployed from the repo.

> The lesson: "prod is behind dev" is an assumption, not a finding. Diff both directions, and when
> prod is ahead, ask which one the repo agrees with before moving anything.

---

## Left to do

### 1. The migration ledger is nine behind, and that is a live hazard

Prod's **schema** is aligned — proven by the column diff above. Prod's **`Migrate.Schema_Version`**
is not: nine versions are unrecorded, and their effects are already present (spot-checked
`Security.Clients.Client_Email`, `Gold.Load_Watermark`, the retired journey table, the hygienist
value column — all present or already gone).

    V001 V002 V005 V007 V008 V009    folded into prod's baseline when it was built
    V151 V152 V153                   applied by file deploy, never recorded

**Running `Migrate.ps1` against prod today would attempt all nine.** Some open with DROP. That is
the hazard, and it is not hypothetical — it is one command away.

The fix is a **ledger backfill**: record the nine as applied without running them. That is a
bookkeeping assertion rather than a verification of each file, so it wants the owner's sanction
rather than a quiet script.

### 2. Fabric items still promote by pipeline

Notebooks (9), data pipelines (3), the lakehouse and 12 reports all sit in the `DEV TO PROD`
pipeline and are promoted there, not from this repo — `Fabric/Notebooks/*` are reference copies.
`Stage.Appointments.site_id` is waiting on that.

### 3. Step 13 of the targets release

Drop `Gold.Fact_Daily_Targets` and its loader, once Maple's reports have been watched.
