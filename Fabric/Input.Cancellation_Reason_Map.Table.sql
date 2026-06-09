/****** Object:  Table [Input].[Cancellation_Reason_Map]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[Input].[Cancellation_Reason_Map]', 'U') IS NULL
CREATE TABLE [Input].[Cancellation_Reason_Map] (
    [pk_cancellation_reason_map]    BIGINT IDENTITY NOT NULL,
    [Tenant_ID]                     INT           NOT NULL,
    [Source_Cancellation_Reason]    VARCHAR(255)  NOT NULL,
    [Standard_Cancellation_Reason]  VARCHAR(100)  NOT NULL,
    [DW_Created_At]                 DATETIME2(3)  NOT NULL,
    [DW_Updated_At]                 DATETIME2(3)  NOT NULL
)
GO
