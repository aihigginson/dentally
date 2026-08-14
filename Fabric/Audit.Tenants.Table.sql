DROP TABLE IF EXISTS [Audit].[Tenants]
GO
CREATE TABLE [Audit].[Tenants](
	[Tenant_ID]           [int]           NOT NULL,
	[Client_ID]           [int]           NULL,
	[Tenant_Name]         [varchar](255)  NULL,
	[API_Base_URL]        [varchar](500)  NULL,
	[API_Key]             [varchar](500)  NULL,
	[Dentally_Client_ID]  [varchar](255)  NULL,
	[Dentally_Secret]     [varchar](500)  NULL,
	[Is_Active]           [int]           NULL,
	[Last_Loaded_At]      [varchar](255)  NULL,
	[Notes]               [varchar](1000) NULL,
	[Cutover_Date]        [date]          NULL          -- Dentally go-live = MIN(updated_at) of Treatment Plans; set by Audit.usp_Set_Tenant_Cutover
)
GO
