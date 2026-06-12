/****** Object:  Table [Config].[Treatment_Category_Standard]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Treatment_Category_Standard]
GO
CREATE TABLE [Config].[Treatment_Category_Standard] (
    [Standard_Treatment_Category]  VARCHAR(100)  NOT NULL,
    [Display_Order]                INT           NOT NULL,
    [Is_Active]                    BIT           NOT NULL
)
GO
