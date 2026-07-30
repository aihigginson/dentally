-- =============================================================================
-- Audit.Tenants — seed data
-- =============================================================================
-- One row per configured dental practice.
-- Is_Active  : 1 = include in ETL runs, 0 = skip
-- Last_Loaded_At: ISO8601 UTC timestamp of last successful Bronze load;
--                 used as updated_after on incremental runs
-- API_Key    : Bearer token — store in Azure Key Vault for production
-- =============================================================================

DELETE FROM Audit.Tenants;
GO

INSERT INTO Audit.Tenants (Tenant_ID, Client_ID, Tenant_Name, API_Base_URL, API_Key, Dentally_Client_ID, Dentally_Secret, Is_Active, Last_Loaded_At, Notes)
VALUES
-- REAL Dentally practices only (tenant 100+; loaded via Ingest_Dentally from api.dentally.co;
-- Bearer token in Key Vault dentally-tokens-<env>, NOT API_Key).
-- Synthetic mock (1-4) + seeded (11-14) tenants retired 2026-07-29 -- DEV now mirrors prod:
-- real data only. (Removing them here stops every deploy re-seeding them as active.)
  (100, 100, 'Maple Dental', 'https://api.dentally.co/v1', NULL, NULL, NULL, 1, NULL, 'REAL - first live practice. Token in Key Vault dentally-tokens-dev. Ingested via Ingest_Dentally in Orchestrate_Build.');
GO
