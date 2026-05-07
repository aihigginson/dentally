DROP TABLE IF EXISTS [Security].[Application_Users]
GO
CREATE TABLE [Security].[Application_Users](
	[User_UPN]           [varchar](255) NOT NULL,
	[Client_ID]          [int]          NOT NULL,
	[Display_Name]       [varchar](255) NULL,
	[Maintain_Targets]   [bit]          NOT NULL
)
GO
