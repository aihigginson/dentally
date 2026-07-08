-- =============================================================================
-- Security.Clients — seed data
-- =============================================================================
-- One row per company (client) that subscribes to Analytically.
-- Client_ID is manually assigned — not an identity column.
-- In production each real dental group is a separate client.
-- Both dev tenants are grouped under Client 1 so dev accounts can see all data.
-- =============================================================================

DELETE FROM Security.Clients;
GO

INSERT INTO Security.Clients (Client_ID, Client_Name)
VALUES
-- API tenants
  (1,  'Smile Group (Dev)'),
  (2,  'Bright Dental (Dev)'),
  (3,  'ClearSmile Manchester (Dev)'),
  (4,  'ClearSmile Birmingham (Dev)'),
-- Seeded tenants
  (11, 'Demonstration Practice'),
  (12, 'Elara Dental'),
  (13, 'NorthCity Dental'),
  (14, 'Eastside Dental'),
-- Real practices (loaded via Ingest_Dentally)
  (100, 'Maple Dental');
GO
