--------------------------------------------------------------------
--  Stored Procedure :  Test.usp_Compare
--  Author           :  AIH
--  Initial Date     :  13/06/2026
--  History          :
--    *01     13/06/2026  AIH Initial Release
--    *02     13/06/2026  AIH Persist results into Test.Compare_Result
--  Purpose          :  Compare the latest capture run and RECORD the results
--                      into Test.Compare_Result (one new Run_Id per call), then
--                      return them as two result sets:
--                        1. REGRESSION - Current vs Baseline per metric
--                                        (implicit; Expected_Difference = 0).
--                        2. RECONCILE  - cross-layer rules from
--                                        Test.Comparison_Definition with their
--                                        expected (often non-zero) offsets.
--                      Both share one row shape:
--                        Actual_Difference = Value_A - Value_B
--                        Deviation         = Actual_Difference - Expected_Difference
--                      A small epsilon (0.005) absorbs currency rounding only;
--                      no tolerance band -- the "are we happy" call is human.
--                      Run AFTER Test.usp_Run_Captures.
--  To Run           :  EXEC Test.usp_Compare
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Test].[usp_Compare]
GO
CREATE   PROCEDURE [Test].[usp_Compare]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Eps     decimal(38,4) = 0.005;   -- float/currency rounding only
    DECLARE @Run_Id  uniqueidentifier;
    DECLARE @Now     datetime2(3);
    DECLARE @Run_Tag varchar(200);

    SET @Run_Id  = NEWID();
    SET @Now     = SYSDATETIME();
    SET @Run_Tag = (SELECT MAX(Run_Tag) FROM Test.Capture_Current);

    BEGIN TRY

        ------------------------------------------------------------------
        -- 1. REGRESSION: Current vs Baseline, per metric (implicit rule).
        --    FULL OUTER JOIN so added / removed metrics surface too.
        ------------------------------------------------------------------
        INSERT INTO Test.Compare_Result
            (Run_Id, Compare_Run_At, Run_Tag, Check_Type, Item_Name, Metric_A, Metric_B,
             Value_A, Value_B, Expected_Difference, Actual_Difference, Deviation, Status, Detail)
        SELECT
              @Run_Id
            , @Now
            , @Run_Tag
            , 'REGRESSION'
            , COALESCE(c.Metric_Name, b.Metric_Name)
            , NULL
            , NULL
            , c.Value                              -- Value_A   = current
            , b.Value                              -- Value_B   = baseline
            , 0                                    -- expected variance
            , c.Value - b.Value                    -- actual variance
            , c.Value - b.Value                    -- deviation (expected 0)
            , CASE
                WHEN b.Metric_Name IS NULL               THEN 'NEW (no baseline)'
                WHEN c.Metric_Name IS NULL               THEN 'REMOVED (baseline only)'
                WHEN c.Error_Message IS NOT NULL         THEN 'ERROR (capture failed)'
                WHEN b.Value IS NULL AND c.Value IS NULL THEN 'OK (null)'   -- stable null, benign
                WHEN b.Value IS NULL OR  c.Value IS NULL THEN 'CHANGED'     -- value appeared/disappeared
                WHEN ABS(c.Value - b.Value) > @Eps       THEN 'CHANGED'
                ELSE                                          'OK'
              END
            , c.Error_Message
        FROM Test.Capture_Current  c
        FULL OUTER JOIN Test.Capture_Baseline b
            ON b.Metric_Name = c.Metric_Name;

        ------------------------------------------------------------------
        -- 2. RECONCILE: cross-layer comparisons within the current run.
        ------------------------------------------------------------------
        INSERT INTO Test.Compare_Result
            (Run_Id, Compare_Run_At, Run_Tag, Check_Type, Item_Name, Metric_A, Metric_B,
             Value_A, Value_B, Expected_Difference, Actual_Difference, Deviation, Status, Detail)
        SELECT
              @Run_Id
            , @Now
            , @Run_Tag
            , 'RECONCILE'
            , cd.Comparison_Name
            , cd.Metric_A
            , cd.Metric_B
            , a.Value
            , b.Value
            , cd.Expected_Difference
            , a.Value - b.Value
            , (a.Value - b.Value) - cd.Expected_Difference
            , CASE
                WHEN a.Value IS NULL OR b.Value IS NULL                        THEN 'MISSING metric'
                WHEN ABS((a.Value - b.Value) - cd.Expected_Difference) > @Eps  THEN 'FAIL'
                ELSE                                                                'PASS'
              END
            , NULL
        FROM Test.Comparison_Definition cd
        LEFT JOIN Test.Capture_Current a ON a.Metric_Name = cd.Metric_A
        LEFT JOIN Test.Capture_Current b ON b.Metric_Name = cd.Metric_B
        WHERE cd.Is_Active = 1;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH

    ------------------------------------------------------------------
    -- Return the two result sets for this run (problems first).
    ------------------------------------------------------------------
    SELECT Check_Type, Item_Name, Value_B AS Baseline_Value, Value_A AS Current_Value,
           Actual_Difference AS Variance, Status, Detail AS Current_Error
    FROM Test.Compare_Result
    WHERE Run_Id = @Run_Id AND Check_Type = 'REGRESSION'
    ORDER BY CASE WHEN Status IN ('OK','OK (null)') THEN 1 ELSE 0 END, Item_Name;

    SELECT Check_Type, Item_Name AS Comparison_Name, Metric_A, Value_A, Metric_B, Value_B,
           Actual_Difference, Expected_Difference, Deviation, Status
    FROM Test.Compare_Result
    WHERE Run_Id = @Run_Id AND Check_Type = 'RECONCILE'
    ORDER BY CASE WHEN Status = 'PASS' THEN 1 ELSE 0 END, Comparison_Name;

    RETURN;
END;
GO
