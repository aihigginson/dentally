-- V037 -- Security.Application_Users: per-module menu access flags + Practitioner_Full_Name.
--
-- Booleans gating which App menus/reports each user sees, so modules can be sold as
-- separate subscriptions. Existing menus (Home/Revenue/Patient/Schedule/Clinical/NHS)
-- default ON; the four not-yet-built modules (Day Book, Finance, My Data, Marketing)
-- default OFF. Practitioner_Full_Name scopes a future "My Data" view to one practitioner.
--
-- Fabric can't ADD a NOT NULL column without a DEFAULT, so the columns are nullable and
-- the app treats NULL as no-access (fail-closed). Idempotent: each column is added only
-- if missing, and values are seeded only where still NULL, so a re-run never stomps a
-- manually-changed flag.

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Home')            ALTER TABLE [Security].[Application_Users] ADD [Access_Home]            BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Revenue')         ALTER TABLE [Security].[Application_Users] ADD [Access_Revenue]         BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Patient')         ALTER TABLE [Security].[Application_Users] ADD [Access_Patient]         BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Schedule')        ALTER TABLE [Security].[Application_Users] ADD [Access_Schedule]        BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Clinical')        ALTER TABLE [Security].[Application_Users] ADD [Access_Clinical]        BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_NHS')             ALTER TABLE [Security].[Application_Users] ADD [Access_NHS]             BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Day_Book')        ALTER TABLE [Security].[Application_Users] ADD [Access_Day_Book]        BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Finance')         ALTER TABLE [Security].[Application_Users] ADD [Access_Finance]         BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_My_Data')         ALTER TABLE [Security].[Application_Users] ADD [Access_My_Data]         BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Access_Marketing')       ALTER TABLE [Security].[Application_Users] ADD [Access_Marketing]       BIT;
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID('Security.Application_Users') AND name='Practitioner_Full_Name') ALTER TABLE [Security].[Application_Users] ADD [Practitioner_Full_Name] VARCHAR(255);
GO

-- Seed the current rows: existing menus ON, not-yet-built modules OFF. Only where NULL
-- so re-application is safe.
UPDATE [Security].[Application_Users] SET [Access_Home]     = 1 WHERE [Access_Home]      IS NULL;
UPDATE [Security].[Application_Users] SET [Access_Revenue]  = 1 WHERE [Access_Revenue]   IS NULL;
UPDATE [Security].[Application_Users] SET [Access_Patient]  = 1 WHERE [Access_Patient]   IS NULL;
UPDATE [Security].[Application_Users] SET [Access_Schedule] = 1 WHERE [Access_Schedule]  IS NULL;
UPDATE [Security].[Application_Users] SET [Access_Clinical] = 1 WHERE [Access_Clinical]  IS NULL;
UPDATE [Security].[Application_Users] SET [Access_NHS]      = 1 WHERE [Access_NHS]       IS NULL;
UPDATE [Security].[Application_Users] SET [Access_Day_Book]  = 0 WHERE [Access_Day_Book]  IS NULL;
UPDATE [Security].[Application_Users] SET [Access_Finance]   = 0 WHERE [Access_Finance]   IS NULL;
UPDATE [Security].[Application_Users] SET [Access_My_Data]   = 0 WHERE [Access_My_Data]   IS NULL;
UPDATE [Security].[Application_Users] SET [Access_Marketing] = 0 WHERE [Access_Marketing] IS NULL;
GO
