/****** Object:  Table [Config].[Payment_Plan_Standard]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Payment_Plan_Standard]
GO
CREATE TABLE [Config].[Payment_Plan_Standard] (
    [Standard_Payment_Plan]  VARCHAR(100)  NOT NULL,
    [Display_Order]          INT           NOT NULL,
    [Is_Active]              BIT           NOT NULL
)
GO
