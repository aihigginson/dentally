-- Security.Access_Log
-- Append-only history of each user's access PROFILE assignment, for subscription billing
-- (interval-overlap: a profile held during any part of month M is billable for M) + audit trail.
-- Written by /api/team POST whenever a user's profile changes.
--
-- IDEMPOTENT CREATE (never DROP/CREATE) so the billing history survives warehouse redeploys.
-- No IDENTITY / no DEFAULT (Fabric Warehouse limitations); the app supplies Effective_At.
IF OBJECT_ID('Security.Access_Log') IS NULL
CREATE TABLE [Security].[Access_Log] (
    [Tenant_ID]    [int]          NOT NULL,   -- = Application_Users.Client_ID
    [User_UPN]     [varchar](255) NOT NULL,   -- = Dim_Users.Email / Application_Users.User_UPN
    [Profile_Key]  [varchar](50)  NOT NULL,   -- 'full' | 'clinician' | 'front_office' | 'no_access'
    [Effective_At] [datetime2](3) NOT NULL,   -- when the assignment took effect (app-supplied UTC)
    [Changed_By]   [varchar](255) NULL        -- owner UPN who made the change (NULL = system/seed)
);
GO
