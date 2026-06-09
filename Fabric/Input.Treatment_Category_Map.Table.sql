/****** Object:  Table [Input].[Treatment_Category_Map]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[Input].[Treatment_Category_Map]', 'U') IS NULL
CREATE TABLE [Input].[Treatment_Category_Map] (
    [pk_treatment_category_map]    BIGINT IDENTITY NOT NULL,
    [Tenant_ID]                    INT           NOT NULL,
    [Source_Treatment_Category]    VARCHAR(255)  NOT NULL,
    [Standard_Treatment_Category]  VARCHAR(100)  NOT NULL,
    [DW_Created_At]                DATETIME2(3)  NOT NULL,
    [DW_Updated_At]                DATETIME2(3)  NOT NULL
)
GO
