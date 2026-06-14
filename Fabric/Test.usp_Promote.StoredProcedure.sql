--------------------------------------------------------------------
--  Stored Procedure :  Test.usp_Promote
--  Author           :  AIH
--  Initial Date     :  13/06/2026
--  History          :
--    *01     13/06/2026  AIH Initial Release
--  Purpose          :  Promote the current capture to the baseline ("last
--                      known-good"). Run ONLY after the variances from
--                      Test.usp_Compare have been reviewed and accepted (e.g.
--                      after a deliberate bug fix). Fully replaces the baseline.
--                      Optionally stamp every promoted row with a release tag.
--  To Run           :  EXEC Test.usp_Promote @Release_Tag = 'v1.4.0'
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Test].[usp_Promote]
GO
CREATE   PROCEDURE [Test].[usp_Promote]
(
    @Release_Tag varchar(200) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        TRUNCATE TABLE Test.Capture_Baseline;

        INSERT INTO Test.Capture_Baseline
            (Metric_Name, Value, Captured_At, Run_Tag, Error_Message)
        SELECT
              Metric_Name
            , Value
            , Captured_At
            , COALESCE(@Release_Tag, Run_Tag)
            , Error_Message
        FROM Test.Capture_Current;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH

    RETURN;
END;
GO
