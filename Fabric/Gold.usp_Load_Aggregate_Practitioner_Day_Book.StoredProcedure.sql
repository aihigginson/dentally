--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Practitioner_Day_Book] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Practitioner_Day_Book
--  Author           :  AIH
--  Purpose          :  Per-practitioner Day Book action counts (Open Plans / Cancellations to
--                      rebook / DNAs to rebook / Recalls to action / Days until next 30-min free),
--                      held as TEXT so they can be placed in a matrix ROW area beside Full Name and
--                      scroll with the diary-fill heatmap in one visual. Counts match the Day Book
--                      detail pages' filters. GOLD_AGG: reads Fact_Treatment_Plans / Fact_Appointments
--                      / Fact_Recalls / Aggregate_Site_Practitioner_Current. Full DELETE + INSERT.
--  History          :
--    *01     30/07/2026  AIH Initial release.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Practitioner_Day_Book]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Practitioner_Day_Book]
(
      @Mode        VARCHAR(100)     = 'TEST'
    , @Logging     smallint         = 1
    , @Run_UUID    UNIQUEIDENTIFIER = NULL
    , @Run_Inserts BIGINT OUT
    , @Run_Updates BIGINT OUT
    , @Run_Deletes BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        DELETE FROM Gold.Aggregate_Practitioner_Day_Book;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Aggregate_Practitioner_Day_Book
            (Tenant_ID, fk_Practitioner, Open_Plans, Cancellations_To_Rebook, DNAs_To_Rebook,
             Recalls_To_Action, Days_Until_Next_30_Free, DW_Created_At, DW_Updated_At)
        SELECT
              dp.Tenant_ID
            , dp.pk_Practitioner                                          AS fk_Practitioner
            , CAST(ISNULL(op.cnt, 0) AS VARCHAR(10))                      AS Open_Plans
            , CAST(ISNULL(cx.cnt, 0) AS VARCHAR(10))                      AS Cancellations_To_Rebook
            , CAST(ISNULL(dn.cnt, 0) AS VARCHAR(10))                      AS DNAs_To_Rebook
            , CAST(ISNULL(rc.cnt, 0) AS VARCHAR(10))                      AS Recalls_To_Action
            , CAST(du.days AS VARCHAR(10))                                AS Days_Until_Next_30_Free
            , SYSUTCDATETIME()                                           AS DW_Created_At
            , SYSUTCDATETIME()                                           AS DW_Updated_At
        FROM Gold.Dim_Practitioners dp
        LEFT JOIN (
            SELECT Tenant_ID, fk_Practitioner, COUNT(1) AS cnt
            FROM Gold.Fact_Treatment_Plans
            WHERE Course_Status IN ('In Progress', 'Open - No Appointment')
            GROUP BY Tenant_ID, fk_Practitioner
        ) op ON op.Tenant_ID = dp.Tenant_ID AND op.fk_Practitioner = dp.pk_Practitioner
        LEFT JOIN (
            SELECT Tenant_ID, fk_Practitioner, COUNT(1) AS cnt
            FROM Gold.Fact_Appointments
            WHERE Is_Cancelled = 1 AND Rebooked_Status = 'Not Rebooked'
            GROUP BY Tenant_ID, fk_Practitioner
        ) cx ON cx.Tenant_ID = dp.Tenant_ID AND cx.fk_Practitioner = dp.pk_Practitioner
        LEFT JOIN (
            SELECT Tenant_ID, fk_Practitioner, COUNT(1) AS cnt
            FROM Gold.Fact_Appointments
            WHERE Is_DNA = 1 AND Rebooked_Status = 'Not Rebooked'
            GROUP BY Tenant_ID, fk_Practitioner
        ) dn ON dn.Tenant_ID = dp.Tenant_ID AND dn.fk_Practitioner = dp.pk_Practitioner
        LEFT JOIN (
            SELECT Tenant_ID, fk_Practitioner, COUNT(1) AS cnt
            FROM Gold.Fact_Recalls
            WHERE Retention_Outlook_In_Scope = 1 AND Is_Booked = 0
            GROUP BY Tenant_ID, fk_Practitioner
        ) rc ON rc.Tenant_ID = dp.Tenant_ID AND rc.fk_Practitioner = dp.pk_Practitioner
        LEFT JOIN (
            SELECT Tenant_ID, fk_Practitioner, MIN(Days_Until_Next_30_Mins) AS days
            FROM Gold.Aggregate_Site_Practitioner_Current
            GROUP BY Tenant_ID, fk_Practitioner
        ) du ON du.Tenant_ID = dp.Tenant_ID AND du.fk_Practitioner = dp.pk_Practitioner
        WHERE dp.pk_Practitioner <> -1;
        SET @My_Inserts = @@ROWCOUNT;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
