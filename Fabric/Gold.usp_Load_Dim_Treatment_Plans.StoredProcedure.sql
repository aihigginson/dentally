--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Treatment_Plans] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Treatment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *04     19/05/2026  AIH TRY_CAST + LEFT(,10) for Start_Date/End_Date to handle ISO 8601 +00:00 suffix
--    *05     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *06     22/05/2026  AIH Add Treatment_Plan_Count (1 for real rows, 0 for sentinel) for use in SUM-based measures
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Treatment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Treatment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Treatment_Plans]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Treatment_Plans]
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
            Tenant_ID                                                           AS Tenant_ID,
            CAST(Id AS INT)                                                     AS Treatment_Plan_ID,
            NULLIF(TRIM(Nickname),'')                                           AS Nickname,
            CAST(Patient_ID AS INT)                                             AS Patient_ID,
            CAST(Practitioner_ID AS INT)                                        AS Practitioner_ID,
            CAST(ISNULL(Completed,0) AS BIT)                                    AS Completed,
            TRY_CAST(LEFT(NULLIF(TRIM(Start_Date), ''), 10) AS DATE)            AS Start_Date,
            TRY_CAST(LEFT(NULLIF(TRIM(End_Date),   ''), 10) AS DATE)            AS End_Date,
            TRY_CAST(NULLIF(TRIM(Completed_At),'') AS datetime2(3))             AS Completed_Date,
            TRY_CAST(NULLIF(TRIM(Last_Completed_At),'') AS DATE)                AS Last_Completed_Date,
            CAST(ISNULL(NHS_UDA_Value,0) AS DECIMAL(18,4))                      AS NHS_UDA_Value,
            CAST(ISNULL(NHS_Completed_UDA_Value,0) AS DECIMAL(18,4))            AS NHS_Completed_UDA_Value,
            CAST(ISNULL(Private_Treatment_Value,0) AS DECIMAL(18,4))            AS Private_Treatment_Value,
            TRY_CAST(NULLIF(TRIM(Created_At),'') AS datetime2(3))               AS Created_Date,
            TRY_CAST(NULLIF(TRIM(Updated_At),'') AS datetime2(3))               AS Updated_Date,
            CAST(1 AS INT)                                                       AS Treatment_Plan_Count
        INTO #src
        FROM Silver.Treatment_Plans
        WHERE Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Treatment_Plans tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Treatment_Plan_ID = tgt.Treatment_Plan_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Treatment_Plan <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Nickname                = src.Nickname,
            Patient_ID              = src.Patient_ID,
            Practitioner_ID         = src.Practitioner_ID,
            Completed               = src.Completed,
            Start_Date              = src.Start_Date,
            End_Date                = src.End_Date,
            Completed_Date          = src.Completed_Date,
            Last_Completed_Date     = src.Last_Completed_Date,
            NHS_UDA_Value           = src.NHS_UDA_Value,
            NHS_Completed_UDA_Value = src.NHS_Completed_UDA_Value,
            Private_Treatment_Value = src.Private_Treatment_Value,
            Updated_Date            = src.Updated_Date,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Dim_Treatment_Plans tgt
        INNER JOIN #src src ON tgt.Treatment_Plan_ID = src.Treatment_Plan_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Nickname] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Private_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Nickname] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practitioner_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Completed_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Completed_UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Private_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Treatment_Plan_base BIGINT = ISNULL((SELECT MAX(pk_Treatment_Plan) FROM Gold.Dim_Treatment_Plans WHERE pk_Treatment_Plan > 0), 0);
        INSERT INTO Gold.Dim_Treatment_Plans (
            pk_Treatment_Plan,
            Tenant_ID,
            Treatment_Plan_ID, Nickname, Patient_ID, Practitioner_ID, Completed,
            Start_Date, End_Date, Completed_Date, Last_Completed_Date,
            NHS_UDA_Value, NHS_Completed_UDA_Value, Private_Treatment_Value,
            Created_Date, Updated_Date, Treatment_Plan_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Treatment_Plan_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Treatment_Plan_ID),
            src.Tenant_ID,
            src.Treatment_Plan_ID, src.Nickname, src.Patient_ID, src.Practitioner_ID, src.Completed,
            src.Start_Date, src.End_Date, src.Completed_Date, src.Last_Completed_Date,
            src.NHS_UDA_Value, src.NHS_Completed_UDA_Value, src.Private_Treatment_Value,
            src.Created_Date, src.Updated_Date, src.Treatment_Plan_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Treatment_Plans tgt WHERE tgt.Treatment_Plan_ID = src.Treatment_Plan_ID AND tgt.Tenant_ID = src.Tenant_ID);

        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Treatment_Plans (pk_Treatment_Plan, Tenant_ID, Treatment_Plan_ID, Treatment_Plan_Count, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Treatment_Plans WHERE pk_Treatment_Plan = -1);
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
