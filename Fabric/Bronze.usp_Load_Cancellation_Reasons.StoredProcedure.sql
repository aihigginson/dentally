--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Cancellation_Reasons] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Cancellation_Reasons
--  Author           :  AIH
--  Initital Date    :  15/05/2026
--  History          :
--    *01     15/05/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     19/05/2026  AIH Fix: archived->Active (inverted), reason->Reason; add Reason_Type, Created_At, Updated_At
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Cancellation_Reasons @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Cancellation_Reasons]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Cancellation_Reasons]
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
    DECLARE @My_Inserts  BIGINT = 0;
    DECLARE @My_Updates  BIGINT = 0;
    DECLARE @My_Deletes  BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)                                   AS Tenant_ID
            , LEFT(id, 255)                                                AS ID
            , CASE WHEN archived IN ('True', '1', 'true') THEN 0 ELSE 1 END AS Active
            , LEFT(reason, 255)                                            AS Reason
            , LEFT(reason_type, 255)                                       AS Reason_Type
            , LEFT(created_at,  255)                                       AS Created_At
            , LEFT(updated_at,  255)                                       AS Updated_At
        INTO #src
        FROM Stage.Cancellation_Reasons
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Active       = src.Active
            , tgt.Reason       = src.Reason
            , tgt.Reason_Type  = src.Reason_Type
            , tgt.Created_At   = src.Created_At
            , tgt.Updated_At   = src.Updated_At
            , tgt.DW_Loaded_At = SYSUTCDATETIME()
        FROM Bronze.Cancellation_Reasons AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Cancellation_Reasons (Tenant_ID, ID, Active, Reason, Reason_Type, Created_At, Updated_At, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.Active, src.Reason, src.Reason_Type, src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Cancellation_Reasons tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Cancellation_Reasons AS tgt
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
