--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Contracts
--  Author           :  AIH
--  Initital Date    :  30/04/2026
--  History          :
--    *01     30/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     19/05/2026  AIH Add Name, Notes
--    *04     20/05/2026  AIH Column naming convention fixes (PDS_Plus)
--    *05     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Contracts]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Contracts]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
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
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                                                                    AS Tenant_ID
            , LEFT(id, 255)                                                                                 AS ID
            , LEFT(active, 255)                                                                             AS Active
            , LEFT(contract_number, 255)                                                                    AS Contract_Number
            , LEFT(end_date, 255)                                                                           AS End_Date
            , LEFT(nhs_location_id, 255)                                                                    AS NHS_Location_ID
            , LEFT(nhs_site_id, 255)                                                                        AS NHS_Site_ID
            , LEFT(pds_plus, 255)                                                                           AS PDS_Plus
            , LEFT(site_id, 255)                                                                            AS Site_ID
            , LEFT(start_date, 255)                                                                         AS Start_Date
            , LEFT(target, 255)                                                                             AS Target
            , LEFT(uda_value, 255)                                                                          AS UDA_Value
            , LEFT(uoa_target, 255)                                                                         AS UOA_Target
            , LEFT(uoa_value, 255)                                                                          AS UOA_Value
            , LEFT(name,  255)                                                                              AS Name
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
            , tgt.PDS_Plus        = src.PDS_Plus
            , tgt.Site_ID         = src.Site_ID
            , tgt.Start_Date      = src.Start_Date
            , tgt.Target          = src.Target
            , tgt.UDA_Value       = src.UDA_Value
            , tgt.UOA_Target      = src.UOA_Target
            , tgt.UOA_Value       = src.UOA_Value
            , tgt.Name            = src.Name
            , tgt.Created_At      = src.Created_At
            , tgt.Updated_At      = src.Updated_At
            , tgt.DW_Loaded_At    = SYSUTCDATETIME()
        FROM Bronze.Contracts AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Contracts (Tenant_ID, ID, Active, Contract_Number, End_Date, NHS_Location_ID, NHS_Site_ID, PDS_Plus, Site_ID, Start_Date, Target, UDA_Value, UOA_Target, UOA_Value, Name, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Active, src.Contract_Number, src.End_Date, src.NHS_Location_ID, src.NHS_Site_ID, src.PDS_Plus, src.Site_ID, src.Start_Date, src.Target, src.UDA_Value, src.UOA_Target, src.UOA_Value, src.Name, src.Created_At, src.Updated_At, SYSUTCDATETIME()
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

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
