DROP TABLE IF EXISTS [Security].[User_Tenants]
GO
CREATE TABLE [Security].[User_Tenants](
	[User_UPN]   [varchar](255) NOT NULL,
	[Tenant_ID]  [int]          NOT NULL
)
GO
