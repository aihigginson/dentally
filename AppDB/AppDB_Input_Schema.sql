-- AppDB_Input_Schema.sql
-- Fabric SQL Database (OLTP) schema for the owner-curated target inputs.
--
-- This DB is the SOURCE OF TRUTH for the three Input tables: the app reads/writes here
-- (fast transactional CRUD from the Settings screens), Fabric auto-mirrors it to OneLake,
-- and Orchestrate_Build copies it into WH_Dentally.Input.* for the target-fact builds
-- (option B). See .claude/plans/target-model-build-plan.md.
--
-- Fabric SQL Database = the Azure SQL engine, so full OLTP T-SQL (PK / DEFAULT / DATETIME2)
-- is available here, unlike the Fabric Warehouse. Idempotent: safe to re-run.

IF SCHEMA_ID('Input') IS NULL EXEC('CREATE SCHEMA Input');
GO

-- One curated role per practitioner (SCD-1 overwrite; no history).
IF OBJECT_ID('Input.Practitioner_Role') IS NULL
CREATE TABLE Input.Practitioner_Role (
    Tenant_ID        INT           NOT NULL,
    Practitioner_ID  BIGINT        NOT NULL,   -- Dentally practitioner id (business key)
    Custom_Role      VARCHAR(100)  NOT NULL,
    FTE              DECIMAL(4,2)  NULL,        -- full-time equivalent (feeds FTE-scaled targets); owner-set on the Roles screen
    Updated_At       DATETIME2(3)  NOT NULL CONSTRAINT DF_Practitioner_Role_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By       VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Practitioner_Role PRIMARY KEY (Tenant_ID, Practitioner_ID)
);
GO
-- FTE moved here from Practitioner_Pay after the initial release: add it to an already-provisioned table.
IF COL_LENGTH('Input.Practitioner_Role','FTE') IS NULL
    ALTER TABLE Input.Practitioner_Role ADD FTE DECIMAL(4,2) NULL;
GO

-- Sparse target grid: one row per (FY, Metric, Target_Level). Target_Level = 'Practice' or a Custom_Role.
IF OBJECT_ID('Input.Targets') IS NULL
CREATE TABLE Input.Targets (
    Tenant_ID     INT           NOT NULL,
    FY            SMALLINT      NOT NULL,   -- FY start year (2026 = FY 2026-27)
    Metric        VARCHAR(100)  NOT NULL,   -- = Config.Metric_Definitions.Metric_Key
    Target_Level  VARCHAR(100)  NOT NULL,   -- 'Practice' or a Custom_Role value
    Target_Value  DECIMAL(18,4) NOT NULL,
    Updated_At    DATETIME2(3)  NOT NULL CONSTRAINT DF_Targets_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By    VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Targets PRIMARY KEY (Tenant_ID, FY, Metric, Target_Level)
);
GO

-- One tolerance band per metric (NOT per cell / per FY). pp for % metrics, relative % for count/currency.
IF OBJECT_ID('Input.Metric_Variance') IS NULL
CREATE TABLE Input.Metric_Variance (
    Tenant_ID   INT           NOT NULL,
    Metric      VARCHAR(100)  NOT NULL,
    Variance    DECIMAL(9,4)  NOT NULL,
    Updated_At  DATETIME2(3)  NOT NULL CONSTRAINT DF_Metric_Variance_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By  VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Metric_Variance PRIMARY KEY (Tenant_ID, Metric)
);
GO

IF OBJECT_ID('Input.Roles') IS NULL
CREATE TABLE Input.Roles (
    Tenant_ID   INT           NOT NULL,
    Role_Name   VARCHAR(100)  NOT NULL,
    Updated_At  DATETIME2(3)  NOT NULL CONSTRAINT DF_Input_Roles_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By  VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Roles PRIMARY KEY (Tenant_ID, Role_Name)
);
GO

-- Subscription access state -- SOURCE OF TRUTH for the Subscriptions screen. The app writes here
-- (fast OLTP); Meta.usp_Sync_Input_From_AppDB upserts it into WH.Security.Application_Users, which
-- auth/RLS read (so access changes land after the next sync, not instantly).
IF OBJECT_ID('Input.Application_Users') IS NULL
CREATE TABLE Input.Application_Users (
    User_UPN               VARCHAR(255) NOT NULL,
    Client_ID              INT          NOT NULL,
    Display_Name           VARCHAR(255) NULL,
    Maintain_Targets       BIT          NOT NULL CONSTRAINT DF_AppUsers_MT DEFAULT 0,
    Access_Home            BIT NULL, Access_Revenue BIT NULL, Access_Patient BIT NULL,
    Access_Schedule        BIT NULL, Access_Clinical BIT NULL, Access_NHS BIT NULL,
    Access_Day_Book        BIT NULL, Access_Finance BIT NULL, Access_My_Data BIT NULL, Access_Marketing BIT NULL,
    Practitioner_Full_Name VARCHAR(255) NULL,
    Profile_Key            VARCHAR(50)  NULL,
    Updated_At             DATETIME2(3) NOT NULL CONSTRAINT DF_AppUsers_UA DEFAULT SYSUTCDATETIME(),
    Updated_By             VARCHAR(255) NULL,
    CONSTRAINT PK_Input_Application_Users PRIMARY KEY (User_UPN)
);
GO

-- Append-only subscription profile change log (billing audit); synced to WH.Security.Access_Log.
IF OBJECT_ID('Input.Access_Log') IS NULL
CREATE TABLE Input.Access_Log (
    Tenant_ID    INT          NOT NULL,
    User_UPN     VARCHAR(255) NOT NULL,
    Profile_Key  VARCHAR(50)  NOT NULL,
    Effective_At DATETIME2(3) NOT NULL CONSTRAINT DF_AccessLog_EA DEFAULT SYSUTCDATETIME(),
    Changed_By   VARCHAR(255) NULL
);
GO

-- Per-practitioner associate pay share (% of production) + FTE. FTE feeds Dim_Practitioners.FTE
-- (target scaling); Associate_Pct feeds practitioner P&L. Either may be null. One row/practitioner.
IF OBJECT_ID('Input.Practitioner_Pay') IS NULL
CREATE TABLE Input.Practitioner_Pay (
    Tenant_ID        INT           NOT NULL,
    Practitioner_ID  BIGINT        NOT NULL,   -- Dentally practitioner id (business key)
    Associate_Pct    DECIMAL(6,3)  NULL,
    FTE              DECIMAL(4,2)  NULL,
    Updated_At       DATETIME2(3)  NOT NULL CONSTRAINT DF_Practitioner_Pay_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By       VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Practitioner_Pay PRIMARY KEY (Tenant_ID, Practitioner_ID)
);
GO
