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
	-- Scopes a "My Data" view to a single practitioner (NULL for non-practitioner users).
	[Practitioner_Full_Name] [varchar](255) NULL
)
GO
