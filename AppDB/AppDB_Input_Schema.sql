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

-- Per-tenant practice configuration (general owner-set settings). FY_Start_Month = the calendar
-- month (1-12) the practice's FINANCIAL YEAR starts; default 4 (April, UK standard). Drives the FY
-- boundaries + labels used by targets and year-to-date figures. Jan (1) = a calendar-year FY
-- (label "FYyy", not "FYyy-yy+1").
IF OBJECT_ID('Input.Practice_Config') IS NULL
CREATE TABLE Input.Practice_Config (
    Tenant_ID        INT           NOT NULL,
    FY_Start_Month   TINYINT       NOT NULL CONSTRAINT DF_Practice_Config_FYSM DEFAULT 4,
    Updated_At       DATETIME2(3)  NOT NULL CONSTRAINT DF_Practice_Config_UA DEFAULT SYSUTCDATETIME(),
    Updated_By       VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Practice_Config PRIMARY KEY (Tenant_ID)
);
GO

-- Per-plan monthly capitation fee, EFFECTIVE-DATED. Owner enters one open row per Denplan variant on
-- the Plan Capitation screen; set an early Effective_From_Date to cover history. Reprice by adding a
-- new row with a later Effective_From_Date. Fact_Plan_Capitation values each member-month at the row
-- whose Effective_From_Date <= that month (latest wins); a month with no covering rate gets NO record.
-- Is_Default = the ONE fallback plan whose rate values former members (their true old plan is
-- unrecoverable from Dentally). One default per tenant.
IF OBJECT_ID('Input.Plan_Capitation_Rate') IS NULL
CREATE TABLE Input.Plan_Capitation_Rate (
    Tenant_ID           INT           NOT NULL,
    Payment_Plan_ID     BIGINT        NOT NULL,   -- Dentally payment plan id (business key)
    Effective_From_Date DATE          NOT NULL,   -- rate applies from this month onward
    Monthly_Value       DECIMAL(9,2)  NOT NULL,   -- per-patient monthly capitation fee for this plan
    Is_Default          BIT           NOT NULL CONSTRAINT DF_Plan_Cap_Rate_Default DEFAULT 0,
    Updated_At          DATETIME2(3)  NOT NULL CONSTRAINT DF_Plan_Cap_Rate_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By          VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Plan_Capitation_Rate PRIMARY KEY (Tenant_ID, Payment_Plan_ID, Effective_From_Date)
);
GO

-- Per-tenant billing contact, set on the Subscriptions screen. Primary_Email = the billing owner /
-- primary account (a staff login); Invoice_Email = where the PDF invoice goes (may be an external
-- address, e.g. the practice's accountant -- not necessarily a Dentally user). The invoice mailer
-- reads this directly; kept in AppDB so the Subscriptions save stays instant.
IF OBJECT_ID('Input.Billing_Contact') IS NULL
CREATE TABLE Input.Billing_Contact (
    Tenant_ID     INT           NOT NULL,
    Primary_Email VARCHAR(255)  NULL,
    Invoice_Email VARCHAR(255)  NULL,
    Updated_At    DATETIME2(3)  NOT NULL CONSTRAINT DF_Billing_Contact_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By    VARCHAR(255)  NULL,
    CONSTRAINT PK_Input_Billing_Contact PRIMARY KEY (Tenant_ID)
);
GO

-- =====================================================================
-- Client hierarchy: Client > Region > Area > (Practice) > Site
-- =====================================================================
-- ==> REGION AND AREA ATTACH TO THE SITE, NOT TO THE TENANT. <== A client may run one
-- Dentally tenant covering sites across the whole country, and those sites have to be
-- placeable in different areas. Hanging the tree off the tenant would make that
-- impossible, and it is the shape a large customer is most likely to arrive with.
--
-- Practice stays 1:1 with tenant and is NOT stored here: it is derived. It behaves as a
-- level only when every site in the tenant shares one area; where a tenant's sites span
-- areas, practice is a cross-cutting label rather than a step in the tree, and the
-- hierarchy reads Client > Region > Area > Site for that client.
--
-- These four tables are curated by Analytically admins, not by the customer: ties of
-- tenant to client, then of site to area. A customer-facing bulk upload can come later.
-- Region and Area are auto-created as single pass-throughs for a client that does not
-- use them, and the degeneracy rule then hides them -- a level is hidden when every node
-- at it has exactly one child, so a single-site customer sees no trace of any of this.

-- The client: who we sell to and then serve. Client_ID is the SAME integer already used by
-- Input.Application_Users.Client_ID and Audit.Tenants.Client_ID, so it is assigned, not an
-- identity -- a new value here must not collide with one already issued in the warehouse.
IF OBJECT_ID('Input.Client') IS NULL
CREATE TABLE Input.Client (
    Client_ID    INT           NOT NULL,
    Client_Name  VARCHAR(255)  NOT NULL,
    Is_Active    BIT           NOT NULL CONSTRAINT DF_Input_Client_Is_Active DEFAULT 1,
    Updated_At   DATETIME2(3)  NOT NULL CONSTRAINT DF_Input_Client_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By   VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Client PRIMARY KEY (Client_ID)
);
GO

-- Which client a tenant belongs to. A tenant has exactly one client, hence Tenant_ID alone
-- as the key. This is the admin screen tie that does not exist anywhere in AppDB today --
-- it lives only in Audit.Tenants.Client_ID in the warehouse, which an admin cannot edit.
IF OBJECT_ID('Input.Client_Tenant') IS NULL
CREATE TABLE Input.Client_Tenant (
    Tenant_ID   INT           NOT NULL,
    Client_ID   INT           NOT NULL,
    Updated_At  DATETIME2(3)  NOT NULL CONSTRAINT DF_Input_Client_Tenant_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By  VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Client_Tenant PRIMARY KEY (Tenant_ID),
    CONSTRAINT FK_Input_Client_Tenant_Client FOREIGN KEY (Client_ID) REFERENCES Input.Client (Client_ID)
);
GO

-- A client's regions. Identity keys here, unlike the rest of Input.*: these rows are born
-- in this database rather than mirroring a Dentally business key, and a surrogate lets a
-- region be renamed without orphaning the areas and sites beneath it.
IF OBJECT_ID('Input.Client_Region') IS NULL
CREATE TABLE Input.Client_Region (
    Region_ID    INT           IDENTITY(1,1) NOT NULL,
    Client_ID    INT           NOT NULL,
    Region_Name  VARCHAR(100)  NOT NULL,
    Sort_Order   INT           NOT NULL CONSTRAINT DF_Input_Client_Region_Sort DEFAULT 0,
    Is_Active    BIT           NOT NULL CONSTRAINT DF_Input_Client_Region_Is_Active DEFAULT 1,
    Updated_At   DATETIME2(3)  NOT NULL CONSTRAINT DF_Input_Client_Region_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By   VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Client_Region PRIMARY KEY (Region_ID),
    CONSTRAINT UQ_Input_Client_Region_Name UNIQUE (Client_ID, Region_Name),
    CONSTRAINT FK_Input_Client_Region_Client FOREIGN KEY (Client_ID) REFERENCES Input.Client (Client_ID)
);
GO

-- A region's areas. Client_ID is reachable through Region_ID and is deliberately not
-- repeated: storing it twice invites the two copies to disagree.
IF OBJECT_ID('Input.Client_Area') IS NULL
CREATE TABLE Input.Client_Area (
    Area_ID     INT           IDENTITY(1,1) NOT NULL,
    Region_ID   INT           NOT NULL,
    Area_Name   VARCHAR(100)  NOT NULL,
    Sort_Order  INT           NOT NULL CONSTRAINT DF_Input_Client_Area_Sort DEFAULT 0,
    Is_Active   BIT           NOT NULL CONSTRAINT DF_Input_Client_Area_Is_Active DEFAULT 1,
    Updated_At  DATETIME2(3)  NOT NULL CONSTRAINT DF_Input_Client_Area_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By  VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Client_Area PRIMARY KEY (Area_ID),
    CONSTRAINT UQ_Input_Client_Area_Name UNIQUE (Region_ID, Area_Name),
    CONSTRAINT FK_Input_Client_Area_Region FOREIGN KEY (Region_ID) REFERENCES Input.Client_Region (Region_ID)
);
GO

-- Where each SITE sits in the tree. The grain is the site, which is the whole point: a
-- tenant's sites may be placed in different areas. Site_ID is VARCHAR(50) to match
-- Gold.Dim_Practice_Sites.Site_ID; no foreign key, because sites arrive from Dentally and
-- are not rows in this database.
IF OBJECT_ID('Input.Site_Area') IS NULL
CREATE TABLE Input.Site_Area (
    Tenant_ID   INT           NOT NULL,
    Site_ID     VARCHAR(50)   NOT NULL,
    Area_ID     INT           NOT NULL,
    Updated_At  DATETIME2(3)  NOT NULL CONSTRAINT DF_Input_Site_Area_Updated_At DEFAULT SYSUTCDATETIME(),
    Updated_By  VARCHAR(256)  NULL,
    CONSTRAINT PK_Input_Site_Area PRIMARY KEY (Tenant_ID, Site_ID),
    CONSTRAINT FK_Input_Site_Area_Area FOREIGN KEY (Area_ID) REFERENCES Input.Client_Area (Area_ID)
);
GO
