--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Practitioner_Diaries] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Practitioner_Diaries
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     30/04/2026  AIH Replace CAST AS DATETIME with datetime2(3); TIME -> TIME(0) — Fabric requires explicit precision
--    *03     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Practitioner_Diaries @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Practitioner_Diaries]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Practitioner_Diaries]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Practitioner_Diaries]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        SELECT
            pd.Tenant_ID                                                AS Tenant_ID,
            pd.Id                                                       AS bk_Practitioner_Diary_ID,
            ISNULL(dpr.pk_Practitioner, -1)                             AS fk_Practitioner,
            dd.pk_Date                                                  AS fk_Date_Day,
            CAST(pd.Day AS DATE)                                        AS Day_Date,
            TRY_CAST(NULLIF(TRIM(pd.Start_Time),'') AS TIME(0))            AS Start_Time,
            TRY_CAST(NULLIF(TRIM(pd.Finish_Time),'') AS TIME(0))           AS End_Time,
            1-CAST(ISNULL(pd.Available,0) AS BIT)                       AS Unavailable,
            CASE WHEN pd.Start_Time IS NOT NULL AND pd.Finish_Time IS NOT NULL
                 THEN DATEDIFF(MINUTE,
                        TRY_CAST(NULLIF(TRIM(pd.Start_Time),'') AS datetime2(3)),
                        TRY_CAST(NULLIF(TRIM(pd.Finish_Time),'') AS datetime2(3)))
            END                                                         AS Session_Duration_Mins,
            COALESCE(brk.Total_Break_Mins, 0)                           AS Total_Break_Mins,
            COALESCE(brk.Break_Count, 0)                                AS Break_Count,
            CASE WHEN CAST(ISNULL(pd.Available,0) AS BIT) = 1
                      AND pd.Start_Time IS NOT NULL AND pd.Finish_Time IS NOT NULL
                 THEN DATEDIFF(MINUTE,
                        TRY_CAST(NULLIF(TRIM(pd.Start_Time),'') AS datetime2(3)),
                        TRY_CAST(NULLIF(TRIM(pd.Finish_Time),'') AS datetime2(3)))
                      - COALESCE(brk.Total_Break_Mins, 0)
                 ELSE 0 END                                             AS Available_Clinical_Mins
        INTO #src
        FROM Silver.Practitioner_Diary pd
        LEFT JOIN Gold.Dim_Practitioners dpr ON dpr.Practitioner_ID = CAST(pd.Practitioner_Id AS INT) AND dpr.Tenant_ID = pd.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd           ON dd.Full_Date        = pd.Day
        LEFT JOIN (
            SELECT
                Practitioner_Diary_ID,
                SUM(DATEDIFF(MINUTE,
                    TRY_CAST(NULLIF(TRIM(Start_Time),'') AS datetime2(3)),
                    TRY_CAST(NULLIF(TRIM(End_Time),'') AS datetime2(3))))  AS Total_Break_Mins,
                COUNT(*)                                                AS Break_Count
            FROM Silver.Practitioner_Diary_Breaks
            GROUP BY Practitioner_Diary_ID
        ) brk ON brk.Practitioner_Diary_ID = pd.Id
        WHERE pd.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_Practitioner_Diaries tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Practitioner_Diary_ID = tgt.bk_Practitioner_Diary_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Practitioner         = src.fk_Practitioner,
            fk_Date_Day             = src.fk_Date_Day,
            Day_Date                = src.Day_Date,
            Start_Time              = src.Start_Time,
            End_Time                = src.End_Time,
            Unavailable             = src.Unavailable,
            Session_Duration_Mins   = src.Session_Duration_Mins,
            Total_Break_Mins        = src.Total_Break_Mins,
            Available_Clinical_Mins = src.Available_Clinical_Mins,
            Break_Count             = src.Break_Count,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Fact_Practitioner_Diaries tgt
        INNER JOIN #src src ON tgt.bk_Practitioner_Diary_ID = src.bk_Practitioner_Diary_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Day] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Day_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[End_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Unavailable] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Session_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Total_Break_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Available_Clinical_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Break_Count] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Day] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Day_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[End_Time] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Unavailable] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Session_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Total_Break_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Available_Clinical_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Break_Count] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Practitioner_Diaries (
            Tenant_ID,
            bk_Practitioner_Diary_ID,
            fk_Practitioner, fk_Date_Day,
            Day_Date, Start_Time, End_Time, Unavailable,
            Session_Duration_Mins, Total_Break_Mins, Available_Clinical_Mins, Break_Count,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Practitioner_Diary_ID,
            src.fk_Practitioner, src.fk_Date_Day,
            src.Day_Date, src.Start_Time, src.End_Time, src.Unavailable,
            src.Session_Duration_Mins, src.Total_Break_Mins, src.Available_Clinical_Mins, src.Break_Count,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Practitioner_Diaries tgt WHERE tgt.bk_Practitioner_Diary_ID = src.bk_Practitioner_Diary_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;
        --*********************************
        --**** Procedure logic ends    ****
        --*********************************

    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes

END
GO
