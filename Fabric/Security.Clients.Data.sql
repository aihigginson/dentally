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
-- This file previously carried four dev API tenants and three point-in-time test practices
-- that no longer exist, and because it is DEPLOYED TO BOTH ENVIRONMENTS prod carried all
-- eight of them too: clients with no tenant, no user and no subscription. A client that
-- resolves to nothing fails closed in _get_user_info, so they were inert rather than
-- dangerous -- but they show up in any list of clients, which is no way to read a
-- production table.
--
-- CLIENT 1 IS OURS. It owns no tenant and is granted access to every active one, which is
-- what lets a support login move between practices -- in the reports as well as the app,
-- since RLS resolves through the same junction.
--
-- REAL CLIENTS START AT 100. Everything below that is internal, which is why this is 1 and
-- not some number off the end -- a high id would read as a customer to anyone scanning the
-- table, and the range is the thing that carries the meaning. Client 1 held this role once
-- before: the note this file used to carry said "both dev tenants are grouped under Client 1
-- so dev accounts can see all data".
--
-- DELETE-then-INSERT, so anything edited directly in a warehouse is replaced on the next
-- deploy. Client_Name is therefore the same in both environments by design; dev's tenant
-- display names are overridden in Audit.Tenants, not here.
-- =============================================================================

DELETE FROM Security.Clients;
GO

INSERT INTO Security.Clients (Client_ID, Client_Name)
VALUES
-- Us. Owns no tenant; sees every active one via Security.Client_Tenant_Access.
  (1,   'Analytically'),
-- Demonstration data (dev only; deliberately not a convincing practice name)
  (11,  'Demonstration Practice'),
-- Real practices (loaded via Ingest_Dentally)
  (100, 'Maple Dental');
GO
