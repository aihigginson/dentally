-- =============================================================================
-- Security.Tenants — seed data
-- =============================================================================
-- One row per Dentally tenant (account).
-- Tenant_ID matches the value used throughout Bronze/Silver/Gold.
-- Dentally_Client_ID / Dentally_Secret: OAuth credentials for the Dentally API.
-- Leave NULL until real credentials are provisioned.
-- =============================================================================

DELETE FROM Security.Tenants;
GO

INSERT INTO Security.Tenants (Tenant_ID, Client_ID, Dentally_Client_ID, Dentally_Secret)
VALUES (1, 1, NULL, NULL),
       (2, 1, NULL, NULL);
GO
