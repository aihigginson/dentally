-- IDEMPOTENT CREATE (never DROP/CREATE): the Team screen now writes these rows, so a warehouse
-- redeploy must NOT wipe them. Add columns via guarded ALTER, never by recreating the table.
IF OBJECT_ID('Security.Application_Users') IS NULL
CREATE TABLE [Security].[Application_Users](
	[User_UPN]               [varchar](255) NOT NULL,
	[Client_ID]              [int]          NOT NULL,
	[Display_Name]           [varchar](255) NULL,
	[Maintain_Targets]       [bit]          NOT NULL,
	-- Per-module menu access (basis for separate subscriptions). Nullable because
	-- Fabric can't ADD NOT NULL without a DEFAULT; the app treats NULL as no-access.
	[Access_Home]            [bit]          NULL,
	[Access_Revenue]         [bit]          NULL,
	[Access_Patient]         [bit]          NULL,
	[Access_Schedule]        [bit]          NULL,
	[Access_Clinical]        [bit]          NULL,
	[Access_NHS]             [bit]          NULL,
	[Access_Day_Book]        [bit]          NULL,
	[Access_Finance]         [bit]          NULL,
	[Access_My_Data]         [bit]          NULL,
	[Access_Marketing]       [bit]          NULL,
	-- ==> THE TOP NODE: HOW FAR UP THE HIERARCHY THIS USER MAY LOOK. <== The default
	-- selection when they open a report, and the ceiling on what the drop-down offers.
	-- NULL means the client's root -- everything -- which is what every user had before
	-- this existed, so there is nothing to backfill.
	--
	-- It is NOT a security boundary, deliberately: RLS still grants the whole client,
	-- because an area-vs-group-mean report cannot compute the group mean from rows RLS
	-- has removed. Cross-client is the boundary that carries weight, and that is RLS.
	--
	-- Stored as a STABLE key, never the drop-down text: that text contains the node's
	-- name, so a rename would leave it matching nothing -- failing closed, silently
	-- revoking someone's access with no error raised anywhere.
	[Top_Node_Level]         [varchar](10)  NULL,
	[Top_Node_Key]           [varchar](64)  NULL,
	-- Scopes a "My Data" view to a single practitioner (NULL for non-practitioner users).
	[Practitioner_Full_Name] [varchar](255) NULL
)
GO
-- Profile_Key: the subscription profile assigned via the Team screen (billing basis). Added after
-- the initial release; guarded ALTER for already-provisioned tables.
IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
              WHERE TABLE_SCHEMA = 'Security' AND TABLE_NAME = 'Application_Users' AND COLUMN_NAME = 'Profile_Key')
    ALTER TABLE [Security].[Application_Users] ADD [Profile_Key] [varchar](50) NULL;
GO
