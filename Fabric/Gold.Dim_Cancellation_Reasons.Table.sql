/****** Object:  Table [Gold].[Dim_Cancellation_Reasons]    Script Date: 21/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Cancellation_Reasons]
GO
CREATE TABLE [Gold].[Dim_Cancellation_Reasons](
	[pk_Cancellation_Reason]    [bigint]        NOT NULL,
	[Tenant_ID]                 [int]           NOT NULL,
	[bk_Cancellation_Reason_ID] [VARCHAR](50)   NOT NULL,
	[Is_Active]                 [bit]           NULL,
	[Reason]                    [VARCHAR](255)  NULL,
	[Standard_Cancellation_Reason] [VARCHAR](100) NULL,
	[Reason_Type]               [VARCHAR](50)   NULL,
	[Is_Short_Notice]           [bit]           NULL,
	[Cancellation_Reason_Count] [int]           NOT NULL,
	[DW_Created_At]             [datetime2](6)  NOT NULL,
	[DW_Updated_At]             [datetime2](6)  NOT NULL
)
GO
