/****** Object:  Table [Input].[Payment_Plan_Map]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[Input].[Payment_Plan_Map]', 'U') IS NULL
CREATE TABLE [Input].[Payment_Plan_Map] (
    [pk_payment_plan_map]    BIGINT IDENTITY NOT NULL,
    [Tenant_ID]              INT           NOT NULL,
    [Source_Payment_Plan]    VARCHAR(255)  NOT NULL,
    [Standard_Payment_Plan]  VARCHAR(100)  NOT NULL,
    [DW_Created_At]          DATETIME2(3)  NOT NULL,
    [DW_Updated_At]          DATETIME2(3)  NOT NULL
)
GO
