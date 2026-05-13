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
VALUES (1, 'Smile Group (Dev)'),
       (2, 'Bright Dental (Dev)');
GO
