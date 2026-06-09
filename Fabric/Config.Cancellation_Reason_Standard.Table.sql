/****** Object:  Table [Config].[Cancellation_Reason_Standard]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Cancellation_Reason_Standard]
GO
CREATE TABLE [Config].[Cancellation_Reason_Standard] (
    [Standard_Cancellation_Reason]  VARCHAR(100)  NOT NULL,
    [Display_Order]                 INT           NOT NULL,
    [Is_Active]                     BIT           NOT NULL
)
GO
