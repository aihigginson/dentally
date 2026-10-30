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

### ~~1. The migration ledger~~ — DONE

Prod's ledger was nine versions behind its own schema, so `Migrate.ps1` pointed at prod would have
attempted all nine. Now **45 applied against 45 files in the repo — nothing pending.**

Recorded by `Scripts/Backfill_Migration_Ledger.py`, which carries the evidence measured for each
version and refuses to record one it has none for. Running the files was the alternative and the
worse one: they are individually guarded, but V001 ADDS a column V005 later DROPS and V008/V009
drop a Silver table, and replaying that against a live warehouse to discover it is fine is not a
risk worth taking for bookkeeping.

**Two of the nine looked like real gaps and were not** — both my expectation, found by checking dev
instead of assuming prod was behind:

| | |
|---|---|
| `V001` | `Fact_Invoice_Items.Is_Invoice_Outstanding` is absent on prod **and on dev**. V001 added it; a later `Table.sql` redeploy removed it. "The column V001 added still exists" was the wrong test — the right one is whether the environments agree. |
| `V153` | `Input.Sync_State` is absent from the prod warehouse **and dev's**. The file sits in `Migrations/` but targets the **AppDB**, where both have it with 18 rows. I looked in the wrong database. |

### 2. Fabric items still promote by pipeline

Notebooks (9), data pipelines (3), the lakehouse and 12 reports all sit in the `DEV TO PROD`
pipeline and are promoted there, not from this repo — `Fabric/Notebooks/*` are reference copies.
`Stage.Appointments.site_id` is waiting on that.

### 3. Step 13 of the targets release

Drop `Gold.Fact_Daily_Targets` and its loader, once Maple's reports have been watched.
