--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Contracts
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Contracts]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Contracts]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
    , @Logging      SMALLINT         = 1
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    DECLARE @My_Run_UUID VARCHAR(36);
    DECLARE @My_Error    VARCHAR(4000);
    SET NOCOUNT ON;
    IF @Logging = 1
        EXEC Audit.ETL_Start_Run
            @Run_Process_Name    = 'Bronze.usp_Load_Contracts',
            @Run_Process_Options = CONCAT('@Tenant_ID = ', @Tenant_ID, ', @Full_Refresh = ', @Full_Refresh),
            @Run_UUID            = @My_Run_UUID OUTPUT,
            @Parent_Run_UUID     = ISNULL(CONVERT(VARCHAR(36), @Run_UUID), '00000000-0000-0000-0000-000000000000');

    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                                                                    AS Tenant_ID
            , LEFT(id, 255)                                                                                 AS ID
            , CASE WHEN active IN ('True', '1', 'true') THEN 1 ELSE 0 END                                  AS Active
            , LEFT(contract_number, 255)                                                                    AS Contract_Number
            , LEFT(end_date, 255)                                                                           AS End_Date
            , LEFT(nhs_location_id, 255)                                                                    AS NHS_Location_ID
            , LEFT(nhs_site_id, 255)                                                                        AS NHS_Site_ID
            , CASE WHEN pds_plus IN ('True', '1', 'true') THEN 1 ELSE 0 END                                AS Pds_Plus
            , LEFT(site_id, 255)                                                                            AS Site_ID
            , LEFT(start_date, 255)                                                                         AS Start_Date
            , LEFT(target, 255)                                                                             AS Target
            , LEFT(uda_value, 255)                                                                          AS UDA_Value
            , LEFT(uoa_target, 255)                                                                         AS UOA_Target
            , LEFT(uoa_value, 255)                                                                          AS UOA_Value
            , LEFT(created_at, 255)                                                                         AS Created_At
            , LEFT(updated_at, 255)                                                                         AS Updated_At
        INTO #src
        FROM Stage.Contracts
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Active          = src.Active
            , tgt.Contract_Number = src.Contract_Number
            , tgt.End_Date        = src.End_Date
            , tgt.NHS_Location_ID = src.NHS_Location_ID
            , tgt.NHS_Site_ID     = src.NHS_Site_ID
            , tgt.Pds_Plus        = src.Pds_Plus
            , tgt.Site_ID         = src.Site_ID
            , tgt.Start_Date      = src.Start_Date
            , tgt.Target          = src.Target
            , tgt.UDA_Value       = src.UDA_Value
            , tgt.UOA_Target      = src.UOA_Target
            , tgt.UOA_Value       = src.UOA_Value
            , tgt.Updated_At      = src.Updated_At
            , tgt.DW_Loaded_At    = SYSUTCDATETIME()
        FROM Bronze.Contracts AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Contracts (Tenant_ID, ID, Active, Contract_Number, End_Date, NHS_Location_ID, NHS_Site_ID, Pds_Plus, Site_ID, Start_Date, Target, UDA_Value, UOA_Target, UOA_Value, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Active, src.Contract_Number, src.End_Date, src.NHS_Location_ID, src.NHS_Site_ID, src.Pds_Plus, src.Site_ID, src.Start_Date, src.Target, src.UDA_Value, src.UOA_Target, src.UOA_Value, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Contracts tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Contracts AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

        IF @Logging = 1
            EXEC Audit.ETL_Finish_Run
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'SUCCEEDED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes;
    END TRY
    BEGIN CATCH
        IF @Logging = 1
        BEGIN
            SET @My_Error = Audit.ETL_Error_Handler();
            EXEC Audit.ETL_Finish_Run
                @Run_UUID      = @My_Run_UUID,
                @Run_Status    = 'FAILED',
                @Rows_Inserted = @My_Inserts,
                @Rows_Updated  = @My_Updates,
                @Rows_Deleted  = @My_Deletes,
                @Error         = @My_Error;
        END
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
