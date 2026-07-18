# Concierge onboarding runbook — put a real practice on a 30-day trial (PROD)

One checklist = the proven Dentally onboarding (Maple-style, see `DENTALLY_ONBOARDING.md` for the Fabric
detail) **+** the trial/billing setup. For the first cohort we do this by hand; self-serve is the fast-follow.

## Prereqs (once)
- V101 + **V102** deployed to prod; prod AppDB has `Input.Billing_Contact` (deployment-pipeline promote);
  the app dev→main PR merged. Prod Fabric has `Ingest_Dentally` + `LH_Dentally` attached (from go-live).

## Per practice
1. **Dentally token** — the practice generates a personal access token; store it:
   `dentally-tokens-prod` = `{"<Tenant_ID>": {"token":"...", "base_url":"https://api.dentally.co/v1", "name":"<Practice>"}}`
   (use the next free Tenant_ID; step 2 tells you which.)
2. **Provision the tenant** (allocates the tenant + full access chain + 30-day trial billing + Access_Log):
   ```sql
   DECLARE @tid INT;
   EXEC Audit.usp_Provision_Tenant
        @Practice_Name = '<Practice>',
        @Principal_Email = '<owner@practice>',            -- their M365 sign-in = the primary account
        @Paid_From = ...,                                  -- today + 30 days  (the trial end)
        @Dentally_Practice_ID = '<id>',
        @Tenant_ID = @tid OUTPUT;
   SELECT @tid;   -- use this Tenant_ID in the KV token key (step 1)
   ```
   (Free-forever partner? set @Paid_From far future, e.g. 2100-01-01.)
3. **First data pull** — run `Ingest_Dentally` STANDALONE (`only_tenant=<tid>`, `sample_pages=0`); it's
   multi-hour + rate-limited (ask Dentally to raise the migration limit). Then run `Orchestrate_Build`
   (`run_dentally_ingest=False`, `tenants_override=[<tid>]`) → Bronze→Gold + model refresh.
4. **Subscriptions + billing contact** — the owner opens Settings → Subscriptions, assigns profiles, ticks
   the **Primary** account and sets the **Invoice email** (or seed it). Nightly/sync applies it.
5. **Verify isolation** — `Scripts\Check_RLS_Isolation.ps1 -Upn <owner@practice>` (sees only their tenant).
6. **Hand over** — they sign in with their **Microsoft 365** account (already multi-tenant) → see their
   reports + the **trial banner** ("N days left"). At day 30 they set up a paid subscription (Stripe, when
   built) or it expires (banner flips to "trial ended"; `_get_user_info` fails closed once you flip
   `Is_Active=0` / they cancel).

## Notes
- **Rate limit** = 3,600 req/clock-hour; the first pull is the slow bit. Stagger overnight, or get it raised.
- **Cancel** → immediate revoke + data deleted within 28 days (`/api/cancel` / `Account_Billing.Delete_By`).
- The **provision SP is optional** — you can do the access-chain/billing by hand as with Maple; the SP just
  makes it one call.
