-- =============================================================================
-- Security.Tenants — seed data
-- =============================================================================
-- Maps Dentally tenants to Analytically clients (companies).
-- Client_ID determines which application users can see which tenants via
-- PBI.[Application Users] (used by both the Flask app and PBI RLS filter).
--
-- Dentally_Client_ID / Dentally_Secret: OAuth credentials for the real
-- Dentally API. NULL for dev/mock environments — Bearer token is stored
-- in Audit.Tenants.API_Key instead.
--
-- Dev setup: Tenant 1 under Client 1 (dev accounts); Tenant 2 under
-- Client 2 (no Application_Users assigned, so RLS blocks it for dev users).
-- =============================================================================

DELETE FROM Security.Tenants;
GO

INSERT INTO Security.Tenants (Tenant_ID, Client_ID, Dentally_Client_ID, Dentally_Secret)
VALUES (1, 1, NULL, NULL),
       (2, 2, NULL, NULL);
GO
