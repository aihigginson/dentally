/****** Object:  Table [Input].[Acquisition_Source_Map]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[Input].[Acquisition_Source_Map]', 'U') IS NULL
CREATE TABLE [Input].[Acquisition_Source_Map] (
    [pk_acquisition_source_map]    BIGINT IDENTITY NOT NULL,
    [Tenant_ID]                    INT           NOT NULL,
    [Source_Acquisition_Source]    VARCHAR(255)  NOT NULL,
    [Standard_Acquisition_Source]  VARCHAR(100)  NOT NULL,
    [DW_Created_At]                DATETIME2(3)  NOT NULL,
    [DW_Updated_At]                DATETIME2(3)  NOT NULL
)
GO
