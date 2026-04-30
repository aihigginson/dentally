--------------------------------------------------------------------
--  Stored Procedure :  Audit.ETL_Start_Run
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Audit.ETL_Start_Run @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Audit].[ETL_Start_Run]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


DROP PROCEDURE IF EXISTS [Audit].[ETL_Start_Run]
GO
CREATE   PROCEDURE [Audit].[ETL_Start_Run]
(
      @Run_Process_Name     VARCHAR(1000)
    , @Run_Process_Options  VARCHAR(8000)
    , @Run_UUID             VARCHAR(36) OUT
    , @Parent_Run_UUID      VARCHAR(36) = '00000000-0000-0000-0000-000000000000'
    , @Process_Type         VARCHAR(50) = 'PROCEDURE'
)
AS
BEGIN
    DECLARE @Start_Time      DATETIME2(6) = SYSDATETIME();
    DECLARE @Status          VARCHAR(50)  = 'STARTED';
    DECLARE @Workspace_Name  VARCHAR(255);
    DECLARE @Lakehouse_Name  VARCHAR(255);
    DECLARE @Warehouse_Name  VARCHAR(255);
    DECLARE @Server_Name     VARCHAR(255) = @@SERVERNAME;
    DECLARE @Database_Name   VARCHAR(255) = DB_NAME();
    DECLARE @Executed_By     VARCHAR(255) = USER_NAME();
    DECLARE @Run_Date        DATE         = DATETRUNC(DAY, @Start_Time);
    DECLARE @UUID            UNIQUEIDENTIFIER;

    -- Get environment details
    SELECT @Workspace_Name = ISNULL(Env_Config_Value, '?Workspace?')
    FROM Audit.Environment_Config
    WHERE Env_Config_Key = 'workspace_name';

    SELECT @Lakehouse_Name = ISNULL(Env_Config_Value, '?Lakehouse?')
    FROM Audit.Environment_Config
    WHERE Env_Config_Key = 'lakehouse_name';

    SELECT @Warehouse_Name = ISNULL(Env_Config_Value, '?Warehouse?')
    FROM Audit.Environment_Config
    WHERE Env_Config_Key = 'warehouse_name';

    -- Generate UUID for this run
    SELECT @UUID = NEWID();
    SELECT @Run_UUID = CONVERT(VARCHAR(36), @UUID);

    -- Insert record into execution log
    INSERT INTO Audit.Process_Execution_Log
    (
          Run_UUID
        , Process_Name
        , Process_Type
        , Start_Time
        , Status
        , Workspace_Name
        , Lakehouse_Name
        , Warehouse_Name
        , Server_Name
        , Database_Name
        , Executed_By
        , Run_Date
        , Process_Options
        , Parent_Run_UUID
    )
    VALUES
    (
          @UUID
        , @Run_Process_Name
        , @Process_Type
        , @Start_Time
        , @Status
        , @Workspace_Name
        , @Lakehouse_Name
        , @Warehouse_Name
        , @Server_Name
        , @Database_Name
        , @Executed_By
        , @Run_Date
        , @Run_Process_Options
        , @Parent_Run_UUID
    );

    -- Return a result set for ADF
    SELECT @Run_UUID AS ADF_UUID;
END;
GO
