-- Security.Access_Log
-- Append-only audit of per-module access grants/revokes. Written by the app (/api/team POST)
-- on every change to Security.Application_Users. Billing reads it by interval-overlap: a
-- (User_UPN, Module_Key) is billable for month M if a grant window overlaps M.
--
-- IDEMPOTENT CREATE (never DROP/CREATE) so the billing history survives warehouse redeploys.
-- No IDENTITY / no DEFAULT (Fabric Warehouse limitations); the app supplies Effective_At.
IF OBJECT_ID('Security.Access_Log') IS NULL
CREATE TABLE [Security].[Access_Log] (
    [Tenant_ID]    [int]          NOT NULL,   -- = Application_Users.Client_ID
    [User_UPN]     [varchar](255) NOT NULL,   -- = Dim_Users.Email / Application_Users.User_UPN
    [Module_Key]   [varchar](50)  NOT NULL,   -- 'Home','Revenue',... (Access_* without the prefix)
    [Action]       [varchar](10)  NOT NULL,   -- 'grant' | 'revoke'
    [Effective_At] [datetime2](3) NOT NULL,   -- when the change took effect (app-supplied UTC)
    [Changed_By]   [varchar](255) NULL        -- owner UPN who made the change (NULL = system/seed)
);
GO
