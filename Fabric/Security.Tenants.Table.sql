DROP TABLE IF EXISTS [Security].[Tenants]
GO
CREATE TABLE [Security].[Tenants](
	[Tenant_ID]           [int]          NOT NULL,
	[Client_ID]           [int]          NOT NULL,
	[Dentally_Client_ID]  [varchar](255) NULL,
	[Dentally_Secret]     [varchar](500) NULL
)
GO
