--EXEC [Audit].[usp_Run_Single_Job] @Proc_Name='Gold.usp_Load_Fact_Appointments';
--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Run_Single_Job
--  Author           :  AIH
--  Initital Date    :  27/07/2026
--  History          :
--    *01     27/07/2026  AIH Initial Release -- re-run one job without hand-writing the
--                            @Run_Inserts / @Run_Updates / @Run_Deletes wrapper every time.
--  To Run           :   EXEC Audit.usp_Run_Single_Job @Proc_Name='Gold.usp_Load_Fact_Appointments'          -- @Mode defaults to 'PROD'
--                       EXEC Audit.usp_Run_Single_Job @Proc_Name='Gold.usp_Load_Dim_Patients', @Mode='TEST'
--                       EXEC Audit.usp_Run_Single_Job @Proc_Name='Meta.usp_Create_Gold_Views', @Mode=NULL   -- job that has no @Mode
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Audit].[usp_Run_Single_Job]
GO
CREATE PROCEDURE [Audit].[usp_Run_Single_Job]
(
      @Proc_Name  SYSNAME                  -- schema-qualified job, e.g. 'Gold.usp_Load_Fact_Appointments'
    , @Mode       VARCHAR(100) = 'PROD'    -- passed to the job's @Mode; pass NULL for a job with no @Mode
)
AS
BEGIN
    SET NOCOUNT ON;

    -- The three counts every build job reports back.
    DECLARE @Run_Inserts BIGINT = 0
          , @Run_Updates BIGINT = 0
          , @Run_Deletes BIGINT = 0;

    -- Always pass the three OUT params by name; only pass @Mode when supplied.
    DECLARE @sql NVARCHAR(MAX) =
        N'EXEC ' + @Proc_Name
        + CASE WHEN @Mode IS NULL THEN N'' ELSE N' @Mode = @p_mode,' END
        + N' @Run_Inserts = @i OUTPUT, @Run_Updates = @u OUTPUT, @Run_Deletes = @d OUTPUT;';

    EXEC sys.sp_executesql
          @sql
        , N'@p_mode VARCHAR(100), @i BIGINT OUTPUT, @u BIGINT OUTPUT, @d BIGINT OUTPUT'
        , @p_mode = @Mode
        , @i = @Run_Inserts OUTPUT
        , @u = @Run_Updates OUTPUT
        , @d = @Run_Deletes OUTPUT;

    PRINT @Proc_Name + N'  ->  Inserts=' + CAST(@Run_Inserts AS VARCHAR(20))
        + N', Updates=' + CAST(@Run_Updates AS VARCHAR(20))
        + N', Deletes=' + CAST(@Run_Deletes AS VARCHAR(20));

    SELECT @Proc_Name AS Job
         , @Run_Inserts AS Inserts
         , @Run_Updates AS Updates
         , @Run_Deletes AS Deletes;
END
GO
