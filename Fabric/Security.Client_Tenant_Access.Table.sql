/****** Object:  Table [Security].[Client_Tenant_Access]    Script Date: 27/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Security.Client_Tenant_Access
--  Author :  AIH
--  Date   :  27/09/2026
--
--  WHICH TENANTS A CLIENT MAY SEE. Many-to-many, and that is the whole point of it.
--
--  Access used to be read straight off Audit.Tenants.Client_ID, which is a COLUMN on the
--  tenant -- so a tenant belonged to exactly one client. That supported one client owning
--  several tenants (a group with more than one Dentally instance) but never one tenant being
--  visible to more than one client, and those are different requirements.
--
--  It mattered as soon as our own people needed to see every practice. The original trick was
--  to repoint the dev tenants' Client_ID at a single client -- see the comment on
--  Security.Clients.Data.sql, "both dev tenants are grouped under Client 1 so dev accounts can
--  see all data". That works only while every tenant is one of ours. Folding a real customer's
--  tenant into an Analytically client would take it away from the client its own staff sign in
--  under, and lock them out of their own practice.
--
--  So ownership and visibility are now separate concerns:
--      Audit.Tenants.Client_ID   -- who OWNS the tenant (billing, subscription, invoices)
--      this table                -- who may SEE it (RLS, the app's practice picker)
--
--  Seeded so that every client keeps access to the tenants it owns, which makes the change
--  behaviour-preserving on the day it ships; the Analytically client is then additive.
--
--  VENDOR-MANAGED, so IDEMPOTENT CREATE and never DROP/CREATE -- same reasoning as
--  Security.Application_Users. A warehouse redeploy must not silently revoke access. Add
--  columns with a guarded ALTER.
--
--  NOT sourced from the AppDB. Every other Input table is practice-curated and reaches the
--  warehouse through Meta.usp_Sync_Input_From_AppDB, which DELETEs and reloads. Visibility is
--  ours to grant and must not be reachable from the same path a practice admin edits their own
--  team through.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('Security.Client_Tenant_Access') IS NULL
CREATE TABLE [Security].[Client_Tenant_Access](
    [Client_ID]   [int]          NOT NULL,
    [Tenant_ID]   [int]          NOT NULL,
    [Granted_At]  [datetime2](3)     NULL,
    [Granted_By]  [varchar](256)     NULL
)
GO
