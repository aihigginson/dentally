--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Treatments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     19/05/2026  AIH Fix nomenclature field name (was name); add active, nhs_treatment_cat, uda_band, treatment_category_id, patient_nomenclature, description, created_at, updated_at; fix ID/Code types
--    *04     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Treatments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Treatments]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Treatments]
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
              TRY_CAST(tenant_id AS INT)   AS Tenant_ID
            , TRY_CAST(id        AS INT)   AS ID
            , LEFT(nomenclature,   255)    AS Nomenclature
            , LEFT(code,           255)    AS Code
            , LEFT(active, 255)                                                              AS Active
            , LEFT(nhs_treatment_cat,     255) AS NHS_Treatment_Cat
            , TRY_CAST(uda_band         AS DECIMAL(18,4)) AS UDA_Band
            , TRY_CAST(treatment_category_id AS DECIMAL(18,4)) AS Treatment_Category_ID
            , LEFT(created_at,            255) AS Created_At
            , LEFT(updated_at,            255) AS Updated_At
        INTO #src
        FROM Stage.Treatments
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Nomenclature           = src.Nomenclature
            , tgt.Code                   = src.Code
            , tgt.Active                 = src.Active
            , tgt.NHS_Treatment_Cat      = src.NHS_Treatment_Cat
            , tgt.UDA_Band               = src.UDA_Band
            , tgt.Treatment_Category_ID  = src.Treatment_Category_ID
            , tgt.Created_At             = src.Created_At
            , tgt.Updated_At             = src.Updated_At
            , tgt.DW_Loaded_At           = SYSUTCDATETIME()
        FROM Bronze.Treatments AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Treatments (Tenant_ID, ID, Nomenclature, Code, Active, NHS_Treatment_Cat, UDA_Band, Treatment_Category_ID, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Nomenclature, src.Code, src.Active, src.NHS_Treatment_Cat, src.UDA_Band, src.Treatment_Category_ID, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Treatments tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Treatments AS tgt
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
