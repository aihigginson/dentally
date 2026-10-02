-- =============================================================================
-- Security.Clients -- seed data
-- =============================================================================
-- One row per company (client) that subscribes to Analytically. Client_ID is manually
-- assigned, not an identity column.
--
-- WHICH TENANTS A CLIENT CAN SEE IS NO LONGER HERE, and is no longer one-to-one. It lives in
-- Security.Client_Tenant_Access (V186). Audit.Tenants.Client_ID still records who OWNS a
-- tenant -- billing, subscription, invoicing -- while that junction records who may SEE one.
--
-- CLIENT 1 IS OURS. It owns no tenant and is granted access to every active one, which is
-- what lets a support login move between practices -- in the reports as well as the app,
-- since RLS resolves through the same junction.
--
-- REAL CLIENTS START AT 100. Everything below that is internal, which is why this is 1 and
-- not some number off the end -- a high id would read as a customer to anyone scanning the
-- table, and the range is the thing that carries the meaning.
--
-- ==> NO BLANKET DELETE ANY MORE. <== This file used to open with DELETE FROM Security.Clients,
-- which was safe while the table held nothing but these three rows. It is not safe now:
--   * V151 added Client_Email, Email_Domain and First_Contact_At, written by the APP at signup,
--   * Web/app.py creates PROSPECT clients from id 1000 upwards the moment someone asks for a
--     verification email -- before there is any tenant, user or subscription.
-- A deploy would have deleted every prospect the sales monitor exists to track, and no guard
-- would have noticed because the seed re-inserts the three rows and the row count still looks
-- plausible. Each owned row is asserted on its own instead; rows this file does not own are
-- left alone.
--
-- ==> AND THE DEMONSTRATION PRACTICE IS DEV-ONLY, BUT THIS FILE DEPLOYS TO BOTH. <== Client 11
-- was inserted unconditionally, so PROD carried a client with no tenant (prod has no tenant 11
-- and never has), no user, no subscription and no billing -- a single orphan row, inert in the
-- app because _get_user_info fails closed, but perfectly visible to anything reading the table.
-- Gold.Dim_Client duly derived "no tenant => prospect" and the sales board reported our own
-- demo fixture as the one and only sales lead. It is now tied to the demo TENANT existing, so
-- it appears exactly where the demo data does and nowhere else, with no environment flag to set
-- and nothing to remember -- the same reason Client_Tenant_Access derives its grants rather
-- than listing them.
-- =============================================================================

-- Us. Owns no tenant; sees every active one via Security.Client_Tenant_Access.
IF NOT EXISTS (SELECT 1 FROM [Security].[Clients] WHERE Client_ID = 1)
    INSERT INTO [Security].[Clients] (Client_ID, Client_Name) VALUES (1, 'Analytically');
GO

-- Demonstration data. Deliberately not a convincing practice name, and deliberately present
-- only where tenant 11 is.
IF EXISTS (SELECT 1 FROM [Audit].[Tenants] WHERE Tenant_ID = 11)
   AND NOT EXISTS (SELECT 1 FROM [Security].[Clients] WHERE Client_ID = 11)
    INSERT INTO [Security].[Clients] (Client_ID, Client_Name) VALUES (11, 'Demonstration Practice');
GO

-- ...and withdrawn again where it is not, which is what makes the rule re-runnable rather than
-- a one-off cleanup. Guarded on the junction and the user roster so it can never remove a row
-- something else depends on: if either is populated, that is not the dev fixture.
IF NOT EXISTS (SELECT 1 FROM [Audit].[Tenants] WHERE Tenant_ID = 11)
   AND NOT EXISTS (SELECT 1 FROM [Security].[Client_Tenant_Access] WHERE Client_ID = 11)
   AND NOT EXISTS (SELECT 1 FROM [Security].[Application_Users] WHERE Client_ID = 11)
    DELETE FROM [Security].[Clients] WHERE Client_ID = 11;
GO

-- Real practices (loaded via Ingest_Dentally).
IF NOT EXISTS (SELECT 1 FROM [Security].[Clients] WHERE Client_ID = 100)
    INSERT INTO [Security].[Clients] (Client_ID, Client_Name) VALUES (100, 'Maple Dental');
GO
