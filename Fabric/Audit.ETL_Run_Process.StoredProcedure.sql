--------------------------------------------------------------------
--  Stored Procedure :  Audit.ETL_Run_Process
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     19/06/2026  AIH Add optional @Tenant_ID/@Full_Refresh runtime params; resolve {TID}/{FR}
--                            tokens in Process_Parameters so one config row can serve all tenants
--                            (Bronze "one job per table"). No-op for Silver/Gold (no tokens / NULL args).
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Audit.ETL_Run_Process @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Audit].[ETL_Run_Process]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[ETL_Run_Process]
GO
CREATE   PROCEDURE [Audit].[ETL_Run_Process]
(
      @Process_Code      VARCHAR(100)
    , @Parent_Run_UUID   VARCHAR(36) = '00000000-0000-0000-0000-000000000000'
    , @Tenant_ID         INT         = NULL   -- runtime value for the {TID} token (per-tenant Bronze)
    , @Full_Refresh      BIT         = NULL   -- runtime value for the {FR} token
)
AS
BEGIN
    DECLARE @My_Run_UUID         UNIQUEIDENTIFIER;
    DECLARE @My_Proc_Name        VARCHAR(1000);
    DECLARE @My_Proc_Description VARCHAR(8000);
    DECLARE @My_Proc_Options     VARCHAR(4000);
    DECLARE @My_Proc_Category    VARCHAR(1000);
    DECLARE @My_Proc_Type        VARCHAR(1000);
    DECLARE @My_SQL_Command      NVARCHAR(4000);
    DECLARE @My_Inserts          BIGINT = 0;
    DECLARE @My_Updates          BIGINT = 0;
    DECLARE @My_Deletes          BIGINT = 0;
    DECLARE @Proc_ID             INT;
    DECLARE @My_Out_Vars         VARCHAR(1000) = '@Run_UUID = @ID, @Run_Inserts = @I OUT, @Run_Updates = @U OUT, @Run_Deletes = @D OUT';
    DECLARE @My_Out_Prms         NVARCHAR(1000) = '@ID UNIQUEIDENTIFIER, @I BIGINT OUT, @U BIGINT OUT, @D BIGINT OUT';
    DECLARE @Message             VARCHAR(1000);

    -- Retrieve process config
    SELECT  @My_Proc_Name        = Process_Name,
            @My_Proc_Description = Process_Desc,
            @My_Proc_Options     = Process_Parameters,
            @My_Proc_Category    = Process_Category_Code,
            @My_Proc_Type        = Process_Type_Code
    FROM Audit.Process_Config
    WHERE Process_Code = @Process_Code;

    -- Resolve runtime tokens in the parameter string. The resolved value is used for
    -- BOTH the audit Process_Options (ETL_Start_Run) AND the dynamic call, so the
    -- execution log records the actual tenant. No-op when the args are NULL or the
    -- template has no token (Silver/Gold rows are unaffected).
    IF @Tenant_ID IS NOT NULL
        SET @My_Proc_Options = REPLACE(@My_Proc_Options, '{TID}', CAST(@Tenant_ID AS VARCHAR(10)));
    IF @Full_Refresh IS NOT NULL
        SET @My_Proc_Options = REPLACE(@My_Proc_Options, '{FR}', CAST(@Full_Refresh AS VARCHAR(1)));

    BEGIN TRY

        -- Register start of process
        EXEC Audit.ETL_Start_Run 
                @Run_Process_Name    = @My_Proc_Name,
                @Run_Process_Options = @My_Proc_Options,
                @Run_UUID            = @My_Run_UUID OUTPUT,
                @Parent_Run_UUID     = @Parent_Run_UUID,
                @Process_Type        = @My_Proc_Type;

        IF UPPER(@My_Proc_Type) = 'PROCEDURE'
        BEGIN
            SELECT @Proc_ID = OBJECT_ID(@My_Proc_Name, 'P');

            IF @Proc_ID IS NULL
            BEGIN
                SET @Message = 'ETL_Run_Process:: Procedure not found';
                EXEC Audit.ETL_Log_Message @My_Run_UUID, @My_Proc_Name, @Message, 2;
                THROW 500001, @Message, 16;
            END;

            SET @Message = 'The object_id is: ' + CONVERT(VARCHAR, @Proc_ID);
            EXEC Audit.ETL_Log_Message @My_Run_UUID, @My_Proc_Name, @Message, 0;

            -- Build dynamic procedure call
            SET @My_SQL_Command = @My_Proc_Name + ' ' + @My_Proc_Options + ', ' + @My_Out_Vars;

            SET @Message = 'Procedure call: ' + @My_SQL_Command;
            EXEC Audit.ETL_Log_Message @My_Run_UUID, @My_Proc_Name, @Message, 0;

            EXEC sp_executesql
                    @Statement = @My_SQL_Command,
                    @Params    = @My_Out_Prms,
                    @ID        = @My_Run_UUID,
                    @I         = @My_Inserts OUT,
                    @U         = @My_Updates OUT,
                    @D         = @My_Deletes OUT;
        END

        ELSE IF @My_Proc_Type IN ('SQLSCRIPT', 'PIPELINE', 'PYTHON', 'DAG')
        BEGIN
            SET @Message = 'ETL_Run_Process:: Process type ' + @My_Proc_Type + ' is not yet supported.';
            EXEC Audit.ETL_Log_Message @My_Run_UUID, @My_Proc_Name, @Message, 2;
            THROW 500002, @Message, 16;
        END

        ELSE
        BEGIN
            SET @Message = 'ETL_Run_Process:: Process type ' + @My_Proc_Type + ' is not recognised.';
            EXEC Audit.ETL_Log_Message @My_Run_UUID, @My_Proc_Name, @Message, 2;
            THROW 500003, @Message, 16;
        END;

        -- Register successful finish
        EXEC Audit.ETL_Finish_Run 
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'SUCCEEDED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes;

    END TRY

    BEGIN CATCH
        DECLARE @My_Error  VARCHAR(4000) = Audit.ETL_Error_Handler();
        DECLARE @My_Result VARCHAR(4000) = 'ETL_Run_Process:: Exception caught - see error message';

        EXEC Audit.ETL_Finish_Run
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'FAILED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes,
                @Result        = @My_Result,
                @Error         = @My_Error;
    END CATCH;

    RETURN;
END;
GO
