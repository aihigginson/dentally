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
VALUES
-- API tenants (tenants 1-4 — loaded via Stage_Ingest + Audit.usp_Load_Bronze)
  (1,  1,  'Smile Group (Dev)',          'https://dentally-production.up.railway.app', 'dev-mock-key-abc123',  NULL, NULL, 1, 1, NULL, 'Mock API — Smile Group, Oxford, 3 sites, NHS + ortho'),
  (2,  2,  'Bright Dental (Dev)',        'https://dentally-production.up.railway.app', 'dev-mock-key-tenant2', NULL, NULL, 1, 1, NULL, 'Mock API — Bright Dental, Brighton, 1 site, private'),
  (3,  3,  'ClearSmile Manchester (Dev)','https://dentally-production.up.railway.app', 'dev-mock-key-tenant3', NULL, NULL, 1, 1, NULL, 'Mock API — ClearSmile Manchester, 2 sites, NHS + private'),
  (4,  4,  'ClearSmile Birmingham (Dev)','https://dentally-production.up.railway.app', 'dev-mock-key-tenant4', NULL, NULL, 1, 1, NULL, 'Mock API — ClearSmile Birmingham, 1 site, NHS + private'),
-- Seeded tenants (tenants 11-14 — loaded via Seed_Stage_Test_Data notebook, no API)
  (11, 11, 'Demonstration Practice',     NULL, NULL, NULL, NULL, 1, 0, NULL, 'Seeded test data — Bristol, 3 sites, NHS + ortho, 15,000 patients'),
  (12, 12, 'Elara Dental',               NULL, NULL, NULL, NULL, 1, 0, NULL, 'Seeded test data — Edinburgh, 1 site, private, 7,500 patients'),
  (13, 13, 'NorthCity Dental',           NULL, NULL, NULL, NULL, 1, 0, NULL, 'Seeded test data — Leeds, 2 sites, NHS + private, 7,500 patients'),
  (14, 14, 'Eastside Dental',            NULL, NULL, NULL, NULL, 1, 0, NULL, 'Seeded test data — Nottingham, 1 site, NHS + private, 5,000 patients'),
-- REAL Dentally practices (tenant 100+ - loaded via Ingest_Dentally from api.dentally.co; Bearer token in Key Vault dentally-tokens-<env>, NOT API_Key)
  (100, 100, 'Maple Dental', 'https://api.dentally.co/v1', NULL, NULL, NULL, 1, 1, NULL, 'REAL - first live practice. Token in Key Vault dentally-tokens-dev. Ingested via Ingest_Dentally in Orchestrate_Build.');
GO
