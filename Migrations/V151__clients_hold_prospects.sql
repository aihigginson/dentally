-- V151: Security.Clients holds PROSPECTS, from the moment they ask for a verification code.
--
-- A client is a COMPANY. At the point someone asks for a code there is no tenant and no
-- application user yet, so there is nothing else to attach them to -- and a company that has
-- enquired is exactly what Security.Clients already represents. The client record is therefore
-- created at the TOP of the funnel, not when onboarding completes, so every later stage
-- (verified, key set up, card supplied, card used) hangs off one stable Client_ID.
--
-- ==> THAT Client_ID MUST SURVIVE CONVERSION. <== It is allocated once, when the code is asked
-- for, and never reissued. Audit.Tenants.Client_ID points at it when the practice is finally
-- created. Re-keying at conversion would break the funnel at the exact moment it starts to matter.
--
-- ==> THIS GRANTS NO ACCESS, AND THAT IS BY CONSTRUCTION, NOT BY LUCK. <==
-- Security.vw_User_Tenant_Access -- the view every RLS rule reads -- does NOT reference
-- Security.Clients at all. It joins Application_Users -> Client_Tenant_Access -> Audit.Tenants.
-- A prospect has no row in any of those three, so a prospect client is invisible to RLS. Checked
-- against the view's definition before writing this, because adding rows to a table in the
-- security schema is the kind of change where "probably fine" is not good enough.
--
-- ==> ALTER, NEVER DROP/CREATE. <== Security.Clients holds live rows. The repo's Table.sql
-- convention opens with DROP TABLE IF EXISTS, so deploying a rewritten DDL for this table would
-- delete every client. The columns are added here instead, idempotently.
--
-- Client_Email is the REAL address, not a hash. The hashed form in the app log is telemetry --
-- enough to count a funnel and join its stages. This is the CRM record: you cannot follow up a
-- prospect you cannot email. The two serve different purposes and the hash does not replace this.

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Clients'
                 AND COLUMN_NAME = 'Client_Email')
    EXEC('ALTER TABLE [Security].[Clients] ADD [Client_Email] VARCHAR(256) NULL');
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Clients'
                 AND COLUMN_NAME = 'Email_Domain')
    EXEC('ALTER TABLE [Security].[Clients] ADD [Email_Domain] VARCHAR(255) NULL');
GO
-- When the company first appeared to us: the challenge request. Distinct from a tenant's
-- Access_From, which is when their data started loading.
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Clients'
                 AND COLUMN_NAME = 'First_Contact_At')
    EXEC('ALTER TABLE [Security].[Clients] ADD [First_Contact_At] DATETIME2(3) NULL');
GO
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Clients'
                 AND COLUMN_NAME = 'Created_At')
    EXEC('ALTER TABLE [Security].[Clients] ADD [Created_At] DATETIME2(3) NULL');
GO
-- 'onboarding:challenge' for a self-service prospect, 'seed:owner' for the hand-made rows that
-- predate this. Worth keeping: it distinguishes a company that found us from one we entered.
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Clients'
                 AND COLUMN_NAME = 'Created_By')
    EXEC('ALTER TABLE [Security].[Clients] ADD [Created_By] VARCHAR(100) NULL');
GO

-- Backfill the three rows that existed before this migration, so Dim_Client does not have to
-- treat NULL as a special case. They were created by hand during setup.
UPDATE [Security].[Clients]
SET    Created_By = 'seed:pre-V151'
WHERE  Created_By IS NULL;
GO

-- ==> NOTE DELIBERATELY NOT ADDED: an Is_Prospect FLAG. <== "Prospect" is simply a client with no
-- tenant yet, which Gold.Dim_Client already derives from Tenant_Count = 0. A stored flag would
-- need updating at conversion and would be wrong the moment someone forgot.

-- Sales.Funnel_Event resolved a client through Tenant_ID, which a PROSPECT does not have. Now the
-- challenge log carries client_id, the event can name the client directly and the earliest stages
-- attribute without waiting for a tenant to exist. Tenant_ID stays for the stages that are derived
-- from tenant-keyed sources (invoice_paid from Billing.Stripe_Invoice).
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Sales' AND TABLE_NAME = 'Funnel_Event'
                 AND COLUMN_NAME = 'Client_ID')
    EXEC('ALTER TABLE [Sales].[Funnel_Event] ADD [Client_ID] INT NULL');
GO
