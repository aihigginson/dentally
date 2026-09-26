--DECLARE @i BIGINT=0,@u BIGINT=0,@d BIGINT=0; EXEC [Gold].[usp_Load_Aggregate_Patient_Value] @Mode='PROD',@Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Aggregate_Patient_Value
--  Author           :  AIH
--  Initial Date     :  27/09/2026
--  Notes:
--    Grain   : one row per patient.
--    Pattern : full rebuild (DELETE + INSERT), pk from ROW_NUMBER() -- as
--              Fact_Patient_At_Risk and Fact_Appointment_Journey already do.
--    Sources : Gold.Fact_Revenue (BOTH revenue types), Gold.Fact_Appointments,
--              Gold.Dim_Patients, Gold.Dim_Date.
--
--    ==> READS BOTH REVENUE TYPES, WHICH IS THE ENTIRE POINT. <== Fact_Revenue holds
--    'Invoice' and 'Capitation' rows. The measure this replaces summed a patient-stats
--    column that carries only the invoiced half, so 74% of a membership patient's value was
--    missing. Filtering Revenue_Type here would reintroduce exactly that bug, so it does not.
--
--    ==> THE WINDOW IS MEASURED FROM THE LAST DATE WITH DATA, NOT FROM GETDATE(). <== A
--    warehouse that has not loaded for a few days would otherwise quietly shorten everyone's
--    window and make every patient look less valuable than yesterday.
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Aggregate_Patient_Value]
GO
CREATE PROCEDURE [Gold].[usp_Load_Aggregate_Patient_Value]
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
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        DECLARE @Window_Months SMALLINT = 36;
        DECLARE @Today DATE = CAST(SYSUTCDATETIME() AS DATE);
        DECLARE @From  DATE = DATEADD(MONTH, -@Window_Months, @Today);

        -- Revenue in the window, BOTH types, per patient.
        DROP TABLE IF EXISTS #rev;
        SELECT r.Tenant_ID, r.fk_Patient,
               SUM(CASE WHEN r.Revenue_Type = 'Capitation' THEN 0 ELSE r.Amount END) AS inv,
               SUM(CASE WHEN r.Revenue_Type = 'Capitation' THEN r.Amount ELSE 0 END) AS cap
        INTO   #rev
        FROM   [Gold].[Fact_Revenue] r
        JOIN   [Gold].[Dim_Date] d ON d.pk_Date = r.fk_Date
        WHERE  r.fk_Patient > 0 AND d.Full_Date >= @From AND d.Full_Date <= @Today
        GROUP BY r.Tenant_ID, r.fk_Patient;

        -- Attendance in the same window. Patient appointments only -- fk_Patient > 0 excludes
        -- the lunchtime blocking-out rows, which are not visits and would flatter every count.
        DROP TABLE IF EXISTS #att;
        SELECT a.Tenant_ID, a.fk_Patient,
               COUNT(*) AS attended,
               MAX(CAST(a.Start_Time AS DATE)) AS last_attended
        INTO   #att
        FROM   [Gold].[Fact_Appointments] a
        WHERE  a.fk_Patient > 0 AND a.Is_Completed = 1
          AND  CAST(a.Start_Time AS DATE) >= @From
          AND  CAST(a.Start_Time AS DATE) <= @Today
        GROUP BY a.Tenant_ID, a.fk_Patient;

        DELETE FROM [Gold].[Aggregate_Patient_Value];
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO [Gold].[Aggregate_Patient_Value]
            (pk_Patient_Value, Tenant_ID, fk_Patient, fk_Practice_Site, Window_Months,
             Window_From, Value_Invoiced, Value_Capitation, Value_Total,
             Appointments_Attended, Last_Attended_Date, Value_Per_Year,
             DW_Created_At, DW_Updated_At)
        SELECT
            ROW_NUMBER() OVER (ORDER BY p.Tenant_ID, p.pk_Patient),
            p.Tenant_ID,
            p.pk_Patient,
            ISNULL(s.pk_Practice_Site, -1),
            @Window_Months,
            @From,
            CAST(ISNULL(r.inv, 0) AS DECIMAL(18,4)),
            CAST(ISNULL(r.cap, 0) AS DECIMAL(18,4)),
            CAST(ISNULL(r.inv, 0) + ISNULL(r.cap, 0) AS DECIMAL(18,4)),
            ISNULL(t.attended, 0),
            t.last_attended,
            -- Annualised over the time the patient has actually been on the books inside the
            -- window, so somebody who joined eight months ago is not made to look poor beside
            -- somebody who has been here the whole three years.
            CAST((ISNULL(r.inv, 0) + ISNULL(r.cap, 0)) * 12.0
                 / NULLIF(CASE WHEN p.First_Appointment_Date > @From
                               THEN DATEDIFF(MONTH, p.First_Appointment_Date, @Today)
                               ELSE @Window_Months END, 0) AS DECIMAL(18,4)),
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM [Gold].[Dim_Patients] p
        LEFT JOIN [Gold].[Dim_Practice_Sites] s
               ON s.Tenant_ID = p.Tenant_ID AND s.Site_ID = p.Site_ID
        LEFT JOIN #rev r ON r.Tenant_ID = p.Tenant_ID AND r.fk_Patient = p.pk_Patient
        LEFT JOIN #att t ON t.Tenant_ID = p.Tenant_ID AND t.fk_Patient = p.pk_Patient
        WHERE p.pk_Patient > 0;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #rev;
        DROP TABLE #att;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes
END
GO
