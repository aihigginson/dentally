# Team / Access management + subscription billing — design

Status: **SPEC (agreed 2026-07-15), not built.** Parked behind the target-grid review loop.
Owner-facing self-service: the principal subscribes practice staff, sets each person's module
access, and we bill per-module per-month off a historical monthly snapshot.

## Decisions (2026-07-15)
- **Billing basis = per module held.** Profiles are just presets; a person's monthly charge =
  Σ (price of each module they currently hold). "Charge them for which modules they had access to."
- **Pricing = per-tenant contract.** System default price per module + per-tenant override.
- **Sequencing = spec + park.** Finish the target-grid round first; build this next.

## What already exists (reuse — this is smaller than it sounds)
- **Roster: `Gold.Dim_Users`** — the FULL Dentally staff list (front office included; Dentally
  users ⊋ practitioners). Has `bk_User_ID`, `Tenant_ID`, `Full_Name`, `Email`, `Role`,
  `Permission_Level`, `Site_ID`, `Last_Login_Date`, `Is_Current`. This is the pick-list; **no new
  ingestion needed.** Front-office people who aren't in `Dim_Practitioners` ARE here.
- **Access flags: `Security.Application_Users`** — per app-user login: `User_UPN` (= login email),
  `Display_Name`, `Client_ID`, `Practitioner_Full_Name`, `Maintain_Targets`, and 10 module flags
  `Access_Home/Revenue/Patient/Schedule/Clinical/NHS/Day_Book/Finance/My_Data/Marketing`.
  Tenant via `Client_ID → Audit.Tenants`. Auth (`_get_user_info`/`_get_user_access` in Web/app.py)
  reads these on every request; RLS embed also relies on them. Today hand-seeded via
  `Security.Application_Users.Data.sql`. **This feature is a self-service manager over these rows.**

## Modules (the billable units)
The 10 `Access_*` flags = the billable modules. `Maintain_Targets` = an admin capability bundled
into the Principal profile (open: billable module or free admin flag — default: bundled, not
separately priced).

## Profiles (presets that seed the module toggles)
Default profile is derived from the Dentally `Role` / `Permission_Level`; then tailorable per person
(any manual toggle → "Custom").
- **Principal** — all modules + `Maintain_Targets` (full access).
- **Clinical Practitioner** — Home, Clinical, NHS, Schedule, Patient (no Finance/Marketing/admin).
- **Front Office** — Schedule, Patient (+ maybe Home). No clinical/finance.
- **No access** — subscribed=off, nothing billed.
Module prices should be calibrated so the default bundles ≈ the intended tiers (Principal ~£30,
Clinical ~£5, Front Office ~£2). With per-module billing the "tier price" is emergent.

## Pricing tables (per-tenant contract)
- `Config.Module_Pricing` (system default): `Module_Key`, `Monthly_Price`. Vendor-set.
- `Input.Tenant_Module_Pricing` (override): `Tenant_ID`, `Module_Key`, `Monthly_Price`.
- Effective price = `COALESCE(tenant override, system default)`.
- Per-tenant pricing is **vendor-managed** (not editable by the practice) — seed via SQL / a
  vendor-only screen; NOT exposed on the practice's Team tab.

## Access change history + monthly billing snapshot
Rule: **billed for month M if the user held a module at ANY point during M.**
- **v1 = nightly capture.** The nightly build (Orchestrate_Build) appends the current access state
  to `Billing.Access_Daily` (Tenant_ID, Capture_Date, User_UPN, User_ID, Module_Key). A (user,
  module) is billable for month M if it appears on ANY capture date in M.
- **Monthly rollup** → `Billing.Monthly_Access_Snapshot` (Tenant_ID, Year_Month, User_ID, User_UPN,
  Module_Key, Effective_Price) — DISTINCT modules held that month × that month's effective price
  (price frozen at the month's rate).
- **Bill** = SUM(Effective_Price) per Tenant per Year_Month; also per user / per profile breakdown.
- Trade-off: nightly capture misses access granted-and-removed within one day (day granularity — fine
  for "ever had access"). If intra-day precision is later needed, add an event log
  (`Billing.Access_Log`: grant/revoke + Effective_At) and bill on interval-overlap with M.

## Where state lives (access flags store)
`Security.Application_Users` stays in the **warehouse** (auth + RLS read it live). The app writes
those rows **directly on save** — access edits are an infrequent admin action, so warehouse write
latency is acceptable (unlike the high-frequency target grid, which needed AppDB). Billing artefacts
(`Access_Daily`, `Monthly_Access_Snapshot`, `Tenant_Module_Pricing`) live in **AppDB** (+ OneLake
mirror for reporting). Revisit only if access editing feels slow.

## App API (all gated on Maintain_Targets = principal)
- `GET /api/team` — `Dim_Users` roster (Is_Current, tenant) LEFT JOIN `Application_Users` → each
  person's subscribed?/profile/module flags + monthly cost preview. Caller's own row flagged locked.
- `POST /api/team` — upsert per user: profile + module flags. Writes `Application_Users`
  (provisioning the row: `User_UPN`=Dim_Users.Email, `Client_ID`=tenant client, `Display_Name`,
  `Practitioner_Full_Name` if a practitioner). **Never** lets the caller change their own row
  (self = full access always). Appends to `Billing.Access_Daily`/log on change.
- `GET /api/billing` (later) — the practice's own monthly bill (snapshot rollup).

## Frontend — new Settings sub-tab "Team"
Table of `Dim_Users`: Name · Dentally Role · Email · Site · [Profile dropdown] · [10 module toggles]
· [£/month]. Profile dropdown applies the preset toggles; manual toggle → Custom. Caller's own row
locked ("You — full access"). Footer running total: "N subscribed · £X/month". Save → `/api/team`.

## Open decisions to confirm before/while building
1. **Identity/provisioning.** Does inserting the `Application_Users` row (keyed by the person's
   email) make their MSAL/Entra login work immediately, or does it need an Entra guest invite? If an
   invite is required, "subscribe" must trigger/prompt it. (Confirm the app's Entra auth model.)
2. **`Maintain_Targets`** — billable module or free admin flag bundled with Principal? (default: free)
3. **Actual per-module £** — user to set prices so default bundles ≈ £30/£5/£2.
4. **Snapshot precision** — nightly capture (v1) vs event log (intra-day). Default v1 = nightly.
5. **Who edits per-tenant pricing** — vendor-only (default) vs a hidden admin screen.

## Build order (when un-parked)
1. AppDB: `Billing.Access_Daily`, `Billing.Monthly_Access_Snapshot`, `Input.Tenant_Module_Pricing`;
   warehouse `Config.Module_Pricing` + seed; profile→module + role→profile maps.
2. App: `/api/team` GET/POST (+ self-lock, provisioning, access-daily append).
3. Frontend: Settings "Team" tab.
4. Nightly: capture step in Orchestrate_Build + monthly rollup SP.
5. Billing readout (view / `/api/billing`).

## Subscriptions sync pipeline (10-min access propagation)

The Subscriptions screen writes access to **AppDB** (fast); auth reads the **warehouse** copy, so a
Fabric Data pipeline re-syncs it on a short schedule ("changes take up to 10 min").

**SP:** `Meta.usp_Sync_Access_From_AppDB` — upserts ONLY `Application_Users` + `Access_Log`
(AppDB -> WH.Security.*). ~1s. UPSERT (never wipes auth rows). Separate from the full
`usp_Sync_Input_From_AppDB` (which the nightly build runs) so the 10-min job doesn't race the fact loads.

**Create the pipeline (per environment: dev workspace, then prod workspace):**
1. Workspace -> **New -> Data pipeline**, name `Sync Subscriptions`.
2. Add a **Script** activity (Activities -> Script). Connection = the **WH_Dentally** warehouse.
3. Script:
   ```sql
   DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
   EXEC Meta.usp_Sync_Access_From_AppDB @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
   ```
4. **Schedule** (pipeline -> Schedule): repeat **every 10 minutes**, On.
5. Save. (Auth is via the workspace/pipeline identity that already has WH access -- no secret.)

**Notes:** worst-case propagation = schedule interval + OneLake mirror lag (AppDB->WH), hence "up to
10 min". Negligible capacity (~1s). Idempotent; safe to overlap the nightly build. Drop the interval
to 5 min if faster propagation is wanted.
