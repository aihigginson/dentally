DROP TABLE IF EXISTS [Gold].[Dim_Tenants]
GO
CREATE TABLE [Gold].[Dim_Tenants](
	[pk_Tenant]    [bigint] IDENTITY NOT NULL,
	[Tenant_ID]    [int]          NOT NULL,
	[Tenant_Name]  [varchar](255) NULL,
	[Is_Active]    [bit]          NULL,
	[DW_Created_At] [datetime2](6) NOT NULL,
	[DW_Updated_At] [datetime2](6) NOT NULL
)
GO
