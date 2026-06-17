# Tenant onboarding

How to bring a new client/tenant onto Analytically. Today this is **manual** (a
candidate for automation — see [ROADMAP.md](ROADMAP.md) §8). Do it **per
environment** (dev and prod are separate workspaces/warehouses).

> The three access-control tables (`Audit.Tenants`, `Security.Clients`,
> `Security.Application_Users`) are **environment-specific and managed out of
> git** — never ship dev values to prod. `Audit.Tenants` holds per-tenant
> Dentally API secrets: keep them in a gitignored local `.sql`, never committed.

## Model

`Application_Users.User_UPN → Client_ID` → `Clients.Client_ID` → `Audit.Tenants(Tenant_ID, Client_ID)`.
A user sees their **client's** tenant(s). RLS filters every tenant-bearing table to those tenant IDs.

## Steps

1. **Pick IDs.** Choose a `Tenant_ID` (int) and `Client_ID` (int). A client may own several tenants (e.g. a group with multiple sites under one Dentally instance = one tenant; or multiple tenants).

2. **`Audit.Tenants`** — one row per tenant. Non-secret columns (`Tenant_ID`, `Client_ID`, `Tenant_Name`, `Is_Active`) define ownership + ETL config; the secret columns (`API_Base_URL`, `API_Key`, `Dentally_Client_ID`, `Dentally_Secret`) are the live Dentally API credentials the ingestion uses. For demo/seeded data leave the secrets `NULL`.

3. **`Security.Clients`** — one row: `(Client_ID, Client_Name)`. Use a clear, accurate name (a demo tenant should read "Demonstration", not a real practice name).

4. **`Security.Application_Users`** — one row per user: `(User_UPN, Client_ID, Display_Name, Maintain_Targets)`. `Maintain_Targets = 1` exposes the in-app Targets editor.

5. **Load data.** Run the Fabric **Bronze ingestion pipeline** for the tenant (uses the `Audit.Tenants` API creds), then the **Silver → Gold** loads. The PBI presentation views and reports are shared across tenants — no per-tenant report build needed.

6. **Targets (optional).** Either users with `Maintain_Targets=1` enter them in the app, or bulk-load from a template: `Scripts/Load_Targets_From_Template.py` (filename `T{tenant}_{FY}.xlsx`), then run `Gold.usp_Load_Fact_Targets` + `Gold.usp_Load_Fact_Effective_Targets`.

7. **Refresh the semantic model** so it imports the new tenant's data + the updated `Application_Users` RLS mapping.

8. **Verify isolation (mandatory).** `Scripts/Check_RLS_Isolation.ps1 -Upn <user@…>` — confirm the user sees only their tenant across all tenant-bearing tables. Also run `Check_RLS_Coverage.ps1` if any new tenant-bearing table was added. (The Test Runner SP must remain a workspace **Admin** for impersonation.)

9. **Hand over.** The user signs into the app; the embed token resolves them via `Application_Users` and applies their RLS identity automatically. No per-user PBI sharing needed.

## Notes / gotchas

- If a user maps to a `Client_ID` with **no** `Audit.Tenants` row, they see **nothing** (fail-closed) — complete the chain.
- New tenant data won't appear until the **model is refreshed** (import model).
- Removing a tenant: set `Audit.Tenants.Is_Active = 0` and remove the `Application_Users` rows; the RLS chain then yields nothing for those users.
