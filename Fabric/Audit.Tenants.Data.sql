-- =============================================================================
-- Audit.Tenants — seed data
-- =============================================================================
-- One row per configured dental practice.
-- Is_Active  : 1 = include in ETL runs, 0 = skip
-- Full_Refresh: 1 = next Stage run pulls all records; set to 0 after successful run
-- Last_Loaded_At: ISO8601 UTC timestamp of last successful Bronze load;
--                 used as updated_after on incremental runs
-- API_Key    : Bearer token — store in Azure Key Vault for production
-- =============================================================================

DELETE FROM Audit.Tenants;
GO

INSERT INTO Audit.Tenants (Tenant_ID, Client_ID, Tenant_Name, API_Base_URL, API_Key, Dentally_Client_ID, Dentally_Secret, Is_Active, Full_Refresh, Last_Loaded_At, Notes)
VALUES (1, 1, 'Smile Group (Dev)',    'https://dentally-production.up.railway.app', 'dev-mock-key-abc123',  NULL, NULL, 1, 1, NULL, 'Development tenant — Tenant 1 (Oxford, 3 sites)'),
       (2, 1, 'Bright Dental (Dev)', 'https://dentally-production.up.railway.app', 'dev-mock-key-tenant2', NULL, NULL, 1, 1, NULL, 'Development tenant — Tenant 2 (Brighton, 2 sites)');
GO
