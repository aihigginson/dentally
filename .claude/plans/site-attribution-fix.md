# V042 — Practice-Site attribution fix (appointments)

## Problem
All facts for real Dentally practices resolve `fk_Practice_Site` to the **sentinel (-1)**, so
reporting cannot split by practice site. Confirmed root cause: the **appointment** load lost its
site source.

- Real API carries site on every entity (a **GUID**): most as `site_id`, but **appointments as
  `practitioner_site_id`** (100% populated on Maple/T100). Rooms are unconfigured for Maple, so
  `room_id` is NULL.
- The dimension (`Gold.Dim_Practice_Sites.Site_ID VARCHAR(50)`) and every fact join
  (`dps.Site_ID = TRIM(<fact>.Site_ID)`) are already **string/GUID-safe** — the GUID key is fine.
- Bronze/Silver appointment history shows the regression:
  - `Bronze.usp_Load_Appointments` *06 — **"Remove Site_ID … (not in Dentally API)"** (wrong: it's
    `practitioner_site_id`).
  - `Silver.usp_Load_Appointments` *06 — **"Derive Site_ID via LEFT JOIN Silver.Rooms on Room_ID"** →
    appointment site now comes *only* from the room's site, which is NULL → sentinel.

## Scope
- **Appointments** — real code change (below). This is the only confirmed break.
- **Invoices / Payments / Patients / NHS_Claims / Patient_Referrals / Contracts** — all still read
  `site_id` (VARCHAR) end-to-end; **structurally fine**. Action = *verify* against freshly-built
  real data, no code change expected.
- **No re-pull, no ingest change:** `Ingest_Dentally`'s `t_appointment` already keeps
  `practitioner_site_id` + `room_id`, so both are already in `stage_appointments`. Fix is
  warehouse-only.

## Design (agreed)
Keep the two genuinely-different sites distinct; Gold uses the practitioner one for now.

| layer | practitioner site | room site |
|---|---|---|
| Bronze.Appointments | **+ `Practitioner_Site_ID` VARCHAR(50)** ← `practitioner_site_id` | `Room_ID` (unchanged) |
| Silver.Appointments | **+ `Practitioner_Site_ID` VARCHAR(50)** ← Bronze | rename existing room-derived `Site_ID` → **`Room_Site_ID`** (still LEFT JOIN Silver.Rooms on Room_ID) |
| Gold.Fact_Appointments | `fk_Practice_Site` ← join on **`Practitioner_Site_ID`** (was room-derived `Site_ID`) | room-site kept in Silver for later |

## File-by-file changes
1. **`Fabric/Bronze.Appointments.Table.sql`** — add `[Practitioner_Site_ID] VARCHAR(50) NULL`.
2. **`Fabric/Bronze.usp_Load_Appointments.StoredProcedure.sql`** — read
   `LEFT(practitioner_site_id, 50) AS Practitioner_Site_ID` from Stage; add to UPDATE + INSERT lists.
   (History note: re-adds site, sourced from `practitioner_site_id` not `site_id`.)
3. **`Fabric/Silver.Appointments.Table.sql`** — add `[Practitioner_Site_ID] VARCHAR(50) NULL`;
   rename `[Site_ID]` → `[Room_Site_ID]`.
4. **`Fabric/Silver.usp_Load_Appointments.StoredProcedure.sql`** — add
   `a.Practitioner_Site_ID AS Practitioner_Site_ID`; keep the Rooms-derived value but alias it
   `AS Room_Site_ID`; add both to hash list / UPDATE / INSERT.
5. **`Fabric/Gold.usp_Load_Fact_Appointments.StoredProcedure.sql`** — change the site join to
   `dps.Site_ID = NULLIF(TRIM(a.Practitioner_Site_ID),'')`. `Room_ID` column already carried; no
   Gold DDL change (fk_Practice_Site stays). (Optional later: add `fk_Room_Site`.)

## Dependencies / cross-env
- **Stage column presence:** Bronze reads `practitioner_site_id`, so `stage_appointments` must expose
  it (true for real T100). Synthetic T11–14 from `generate_data.py` emit `site_id`, not
  `practitioner_site_id` → add `practitioner_site_id` to the generator (folds into the pending
  "generator → real shapes" task) so dev tenants also attribute. `mergeSchema` unions the column, so
  mixed-tenant stage is fine (synthetic rows just get NULL until the generator is updated).
- Recreate `Stage.Appointments` view only if the SQL endpoint has a cached schema without the column.
- **PBI:** the "Practice Site" filter now populates for real practices. For single-site Maple it
  becomes a one-item list (correct) — do **not** remove the filter.

## Manifest
`Releases/V042__site_attribution_appointments.manifest`:
- DEPLOY the 2 table DDLs (Bronze.Appointments, Silver.Appointments) — **`ALTER`-safe?** No: these are
  DROP/CREATE `.Table.sql`. Bronze/Silver appointments are reloadable from Stage/Bronze, so DROP/CREATE
  + full reload is acceptable — sequence: deploy DDLs → deploy 3 SPs → EXEC Bronze→Silver→Gold
  appointment loads for affected tenants → (Gold Fact_Appointments rebuild).
- Prefer `ALTER TABLE ADD`/rename where Fabric allows, to avoid a full appointments reload
  (V012 used `ALTER … DROP COLUMN` successfully — check if `ALTER … ADD` + `sp_rename` are viable to
  make this data-preserving).
- No re-baseline expected (site was sentinel before; this is a new correct attribution — but the
  regression metrics that group by site *will* move, so capture + eyeball).

## Validation
- Post-build: `SELECT fk_Practice_Site, COUNT(*) FROM Gold.Fact_Appointments WHERE Tenant_ID=100
  GROUP BY fk_Practice_Site` → expect the real site pk, not -1.
- Repeat the sentinel check for Fact_Invoices/Payments/etc. (should already be non-sentinel).
- `Check_FK_Integrity.sql` should show site coverage improve.

## Open decisions for AIH
- Naming: `Room_Site_ID` for the room-derived column (vs keeping `Site_ID`)? 
- `ALTER`-preserving vs DROP/CREATE+reload for the two appointment tables?
- Revisit **V012's removal of `Treatment_Description`** (it's the appointment/slot type "Hygiene 30",
  needed for reporting) — separate small change, not in this manifest.
