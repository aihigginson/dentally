-- V154: the columns the targets rework needs, on tables that already hold rows.
--
-- ==> TWENTY-TWO COLUMNS THAT ONLY EVER EXISTED ON DEV. <== Every one of these was added by hand to
-- AppDB-dev and the dev warehouse during development and never written down. The chain therefore
-- works perfectly on dev and stops halfway through prod. Found by diffing the two environments
-- rather than by discovering them one failure at a time:
--
--     Input.Targets              Level_Type, Level_Key, Client_ID
--     Input_Stage.Targets        Level_Type, Level_Key, Client_ID
--     Input_Stage.Application_Users  Top_Node_Level, Top_Node_Key
--     Client_ID on Billing_Contact, Metric_Variance, Plan_Capitation_Rate, Practice_Config,
--                   Practitioner_Pay and Practitioner_Role -- in BOTH schemas
--     Plan_Name on Plan_Capitation_Rate -- in both
--
-- ==> ALTER, NEVER DROP/CREATE. <== Two reasons, and both have bitten before. The repo's
-- Input_Stage.*.Table.sql files are guarded by IF OBJECT_ID IS NULL, so re-deploying one against an
-- existing table is a silent no-op and the column never arrives -- which is exactly why
-- Input_Stage.Targets declares Level_Type and Level_Key in its DDL and prod does not have them. And
-- the Input.* DDL files open with DROP TABLE, so deploying those would delete owner-curated rows.
--
-- ==> THIS MUST RUN BEFORE Meta.usp_Sync_Input_From_AppDB IS RE-DEPLOYED. <== The new proc's INSERT
-- column lists name Client_ID and the two Level_ columns. Deploy it first and every sync fails on an
-- invalid column name, which stops Input.* being refreshed at all.
--
-- ==> AND BEFORE THE APPDB MIGRATIONS CAN REACH THE WAREHOUSE. <== Web/appdb_sync.py takes its
-- column list from the TARGET (Input_Stage), so a column AppDB has and staging does not is dropped
-- on the way across, silently. The AppDB side can be migrated first -- it just cannot be SEEN until
-- this lands.
--
-- Every column is NULLABLE, which is what makes this safe on a table holding rows: existing rows
-- take NULL, and Gold.usp_Load_Fact_Node_Targets reads a NULL Level_Type as 'Practice' and a NULL
-- Level_Key as the Tenant_ID, so an un-backfilled row keeps behaving exactly as it always has.
-- Client_ID is backfilled by AppDB.Migration.Client_Keying.sql on the AppDB side and arrives here
-- through the sync, not by an UPDATE here.
--
-- Idempotent: each ALTER is guarded, so a re-run adds nothing and a partially-applied run completes.

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Billing_Contact'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input].[Billing_Contact] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Metric_Variance'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input].[Metric_Variance] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Plan_Capitation_Rate'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input].[Plan_Capitation_Rate] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Plan_Capitation_Rate'
                 AND COLUMN_NAME = 'Plan_Name')
    ALTER TABLE [Input].[Plan_Capitation_Rate] ADD [Plan_Name] VARCHAR(200) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Practice_Config'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input].[Practice_Config] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Practitioner_Pay'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input].[Practitioner_Pay] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Practitioner_Role'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input].[Practitioner_Role] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Targets'
                 AND COLUMN_NAME = 'Level_Type')
    ALTER TABLE [Input].[Targets] ADD [Level_Type] VARCHAR(10) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Targets'
                 AND COLUMN_NAME = 'Level_Key')
    ALTER TABLE [Input].[Targets] ADD [Level_Key] VARCHAR(64) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input' AND TABLE_NAME = 'Targets'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input].[Targets] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Application_Users'
                 AND COLUMN_NAME = 'Top_Node_Level')
    ALTER TABLE [Input_Stage].[Application_Users] ADD [Top_Node_Level] VARCHAR(10) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Application_Users'
                 AND COLUMN_NAME = 'Top_Node_Key')
    ALTER TABLE [Input_Stage].[Application_Users] ADD [Top_Node_Key] VARCHAR(64) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Billing_Contact'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input_Stage].[Billing_Contact] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Metric_Variance'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input_Stage].[Metric_Variance] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Plan_Capitation_Rate'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input_Stage].[Plan_Capitation_Rate] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Plan_Capitation_Rate'
                 AND COLUMN_NAME = 'Plan_Name')
    ALTER TABLE [Input_Stage].[Plan_Capitation_Rate] ADD [Plan_Name] VARCHAR(200) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Practice_Config'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input_Stage].[Practice_Config] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Practitioner_Pay'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input_Stage].[Practitioner_Pay] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Practitioner_Role'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input_Stage].[Practitioner_Role] ADD [Client_ID] INT NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Targets'
                 AND COLUMN_NAME = 'Level_Type')
    ALTER TABLE [Input_Stage].[Targets] ADD [Level_Type] VARCHAR(10) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Targets'
                 AND COLUMN_NAME = 'Level_Key')
    ALTER TABLE [Input_Stage].[Targets] ADD [Level_Key] VARCHAR(64) NULL;

GO

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = 'Input_Stage' AND TABLE_NAME = 'Targets'
                 AND COLUMN_NAME = 'Client_ID')
    ALTER TABLE [Input_Stage].[Targets] ADD [Client_ID] INT NULL;

GO

-- ---- prove it, rather than assume it ---------------------------------------
-- Every column this migration exists to add must now be present. A missing row here means the
-- ALTER was skipped, not that it succeeded quietly.
SELECT c.want_schema + '.' + c.want_table AS table_, c.want_column AS column_,
       CASE WHEN ic.COLUMN_NAME IS NULL THEN 'STILL MISSING' ELSE 'present' END AS state
FROM   (VALUES
           ('Input', 'Billing_Contact', 'Client_ID'),
           ('Input', 'Metric_Variance', 'Client_ID'),
           ('Input', 'Plan_Capitation_Rate', 'Client_ID'),
           ('Input', 'Plan_Capitation_Rate', 'Plan_Name'),
           ('Input', 'Practice_Config', 'Client_ID'),
           ('Input', 'Practitioner_Pay', 'Client_ID'),
           ('Input', 'Practitioner_Role', 'Client_ID'),
           ('Input', 'Targets', 'Level_Type'),
           ('Input', 'Targets', 'Level_Key'),
           ('Input', 'Targets', 'Client_ID'),
           ('Input_Stage', 'Application_Users', 'Top_Node_Level'),
           ('Input_Stage', 'Application_Users', 'Top_Node_Key'),
           ('Input_Stage', 'Billing_Contact', 'Client_ID'),
           ('Input_Stage', 'Metric_Variance', 'Client_ID'),
           ('Input_Stage', 'Plan_Capitation_Rate', 'Client_ID'),
           ('Input_Stage', 'Plan_Capitation_Rate', 'Plan_Name'),
           ('Input_Stage', 'Practice_Config', 'Client_ID'),
           ('Input_Stage', 'Practitioner_Pay', 'Client_ID'),
           ('Input_Stage', 'Practitioner_Role', 'Client_ID'),
           ('Input_Stage', 'Targets', 'Level_Type'),
           ('Input_Stage', 'Targets', 'Level_Key'),
           ('Input_Stage', 'Targets', 'Client_ID')
       ) c (want_schema, want_table, want_column)
LEFT   JOIN INFORMATION_SCHEMA.COLUMNS ic
       ON  ic.TABLE_SCHEMA = c.want_schema AND ic.TABLE_NAME = c.want_table
       AND ic.COLUMN_NAME  = c.want_column
ORDER  BY table_, column_;
