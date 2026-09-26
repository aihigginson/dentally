-- =============================================================================
-- Security.Client_Tenant_Access -- seed
-- =============================================================================
-- Re-runnable. Two statements, in this order, and the order matters:
--
--   1. every client keeps access to the tenants it OWNS (Audit.Tenants.Client_ID). Derived
--      rather than listed, so a tenant onboarded later cannot be left without a grant by
--      somebody forgetting to edit this file.
--   2. the Analytically client sees every ACTIVE tenant. This is what lets our own logins
--      switch between practices -- in the reports as well as the app, because RLS reads the
--      same table.
--
-- Client 999 is deliberately outside the range real clients are assigned from.
-- =============================================================================

IF NOT EXISTS (SELECT 1 FROM [Security].[Clients] WHERE Client_ID = 999)
    INSERT INTO [Security].[Clients] (Client_ID, Client_Name) VALUES (999, 'Analytically');
GO

INSERT INTO [Security].[Client_Tenant_Access] (Client_ID, Tenant_ID, Granted_At, Granted_By)
SELECT t.Client_ID, t.Tenant_ID, SYSUTCDATETIME(), 'seed:owner'
FROM   [Audit].[Tenants] t
WHERE  t.Client_ID IS NOT NULL
  AND  NOT EXISTS (SELECT 1 FROM [Security].[Client_Tenant_Access] a
                    WHERE a.Client_ID = t.Client_ID AND a.Tenant_ID = t.Tenant_ID);
GO

INSERT INTO [Security].[Client_Tenant_Access] (Client_ID, Tenant_ID, Granted_At, Granted_By)
SELECT 999, t.Tenant_ID, SYSUTCDATETIME(), 'seed:analytically'
FROM   [Audit].[Tenants] t
WHERE  ISNULL(t.Is_Active, 1) = 1
  AND  NOT EXISTS (SELECT 1 FROM [Security].[Client_Tenant_Access] a
                    WHERE a.Client_ID = 999 AND a.Tenant_ID = t.Tenant_ID);
GO
