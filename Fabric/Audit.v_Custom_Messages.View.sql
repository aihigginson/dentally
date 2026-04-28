/****** Object:  View [Audit].[v_Custom_Messages]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [Audit].[v_Custom_Messages]
GO
CREATE   VIEW [Audit].[v_Custom_Messages] AS
SELECT 
      [Message_UUID]
    , [Run_UUID]
    , [Process_Name]
    , [Message_Date]
    , CASE [Message_Level] 
          WHEN 0 THEN 'DEBUG' 
          WHEN 1 THEN 'INFO' 
          WHEN 2 THEN 'WARN' 
          WHEN 3 THEN 'ERROR' 
          ELSE 'CUSTOM' 
      END AS [Level]
    , [Message_Text]
FROM Audit.Process_Message_Log
WHERE [Message_Level] NOT IN (0, 1, 2, 3);
GO
