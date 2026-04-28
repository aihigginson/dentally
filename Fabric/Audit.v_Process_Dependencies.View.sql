/****** Object:  View [Audit].[v_Process_Dependencies]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [Audit].[v_Process_Dependencies]
GO
CREATE   VIEW [Audit].[v_Process_Dependencies] AS
SELECT  
      d.[Prev_Process_Code]
    , p.[Process_Name]       AS [Prev_Process_Name]
    , p.[Process_Desc]       AS [Prev_Process_Desc]
    , d.[Next_Process_Code]
    , n.[Process_Name]       AS [Next_Process_Name]
    , n.[Process_Desc]       AS [Next_Process_Desc]
    , d.[Dependency_Type]
    , d.[Dependency_Level]
    , d.[Is_Active]
    , d.[On_Prev_Error]
    , d.[On_Next_Error]
FROM Audit.Process_Dependency AS d
JOIN Audit.Process_Config     AS p ON d.Prev_Process_Code = p.Process_Code
JOIN Audit.Process_Config     AS n ON d.Next_Process_Code = n.Process_Code;
GO
