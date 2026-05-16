--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Recalls] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Recalls
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     13/05/2026  AIH Add First_Reminder_Sent_At from Stage
--    *03     15/05/2026  AIH Align with rebuilt mock API: recall_date, interval_months, notes; remove legacy fields
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Recalls @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Recalls]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Recalls]
(
      @Tenant_ID    INT
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
    , @Full_Refresh BIT    = 0
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id       AS INT)            AS Tenant_ID
            , LEFT(id,                  255)              AS ID
            , TRY_CAST(patient_id      AS DECIMAL(18,4))  AS Patient_ID
            , TRY_CAST(practitioner_id AS DECIMAL(18,4))  AS Practitioner_ID
            , LEFT(site_id,             255)              AS Site_ID
            , LEFT(recall_date,         255)              AS Recall_Date
            , LEFT(recall_type,         255)              AS Recall_Type
            , TRY_CAST(interval_months AS DECIMAL(18,4))  AS Interval_Months
            , LEFT(status,              255)              AS Status
            , CAST(notes AS VARCHAR(MAX))                 AS Notes
            , LEFT(created_at,          255)              AS Created_At
            , LEFT(updated_at,          255)              AS Updated_At
        INTO #src
        FROM Stage.Recalls
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Patient_ID      = src.Patient_ID
            , tgt.Practitioner_ID = src.Practitioner_ID
            , tgt.Site_ID         = src.Site_ID
            , tgt.Recall_Date     = src.Recall_Date
            , tgt.Recall_Type     = src.Recall_Type
            , tgt.Interval_Months = src.Interval_Months
            , tgt.Status          = src.Status
            , tgt.Notes           = src.Notes
            , tgt.Updated_At      = src.Updated_At
            , tgt.DW_Loaded_At    = SYSUTCDATETIME()
        FROM Bronze.Recalls AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Recalls (
            Tenant_ID, ID, Patient_ID, Practitioner_ID, Site_ID,
            Recall_Date, Recall_Type, Interval_Months, Status, Notes,
            Created_At, Updated_At, DW_Loaded_At
        )
        SELECT
            src.Tenant_ID, src.ID, src.Patient_ID, src.Practitioner_ID, src.Site_ID,
            src.Recall_Date, src.Recall_Type, src.Interval_Months, src.Status, src.Notes,
            src.Created_At, src.Updated_At, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Recalls tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Recalls AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE ID = tgt.ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH THROW; END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
