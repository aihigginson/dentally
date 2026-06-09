/****** Object:  Table [Config].[Acquisition_Source_Standard]    Script Date: 09/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Config].[Acquisition_Source_Standard]
GO
CREATE TABLE [Config].[Acquisition_Source_Standard] (
    [Standard_Acquisition_Source]  VARCHAR(100)  NOT NULL,
    [Display_Order]                INT           NOT NULL,
    [Is_Active]                    BIT           NOT NULL
)
GO
