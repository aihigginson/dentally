/****** Object:  View [Audit].[v_48Hr_Processes]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP VIEW IF EXISTS [Audit].[v_48Hr_Processes]
GO
CREATE   VIEW [Audit].[v_48Hr_Processes] AS
SELECT  
      l.[Run_UUID]
    , l.[Process_Name]
    , l.[Process_Type]
    , l.[Start_Time]
    , COALESCE(t.[End_Time], l.[End_Time]) AS [End_Time]
    , COALESCE(t.[Duration_Seconds], l.[Duration_Seconds]) AS [Duration_Seconds]
    , COALESCE(t.[Num_Of_Records], l.[Num_Of_Records]) AS [Num_Of_Records]
    , COALESCE(t.[Status], l.[Status]) AS [Status]
    , COALESCE(t.[Error_Message], l.[Error_Message]) AS [Error_Message]
    , l.[Workspace_Name]
    , l.[Lakehouse_Name]
    , l.[Warehouse_Name]
    , l.[Server_Name]
    , l.[Database_Name]
    , COALESCE(t.[Process_Result], l.[Process_Result]) AS [Process_Result]
    , l.[Executed_By]
    , l.[Run_Date]
    , l.[Process_Options]
    , COALESCE(t.[Rows_Inserted], l.[Rows_Inserted]) AS [Rows_Inserted]
    , COALESCE(t.[Rows_Updated], l.[Rows_Updated]) AS [Rows_Updated]
    , COALESCE(t.[Rows_Deleted], l.[Rows_Deleted]) AS [Rows_Deleted]
    , l.[Parent_Run_UUID]
FROM Audit.Process_Execution_Log AS l
LEFT JOIN Audit.Process_Execution_Temp AS t
    ON l.[Run_UUID] = t.[Run_UUID]
WHERE l.[Start_Time] > DATEADD(day, -2, SYSDATETIME());
GO
