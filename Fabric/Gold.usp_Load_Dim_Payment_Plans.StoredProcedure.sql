--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Payment_Plans
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Payment_Plans @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Payment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Payment_Plans]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Payment_Plans]
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
            Tenant_ID AS Tenant_ID,
            CAST(Payment_Plan_Id AS INT)                                    AS Payment_Plan_ID,
            NULLIF(TRIM(Payment_Plan_Name),'')                              AS Payment_Plan_Name,
            NULLIF(TRIM(Payment_Plan_Patient_Friendly_Name),'')             AS Patient_Friendly_Name,
            CAST(ISNULL(Payment_Plan_Active,0) AS BIT)                      AS Active,
            NULLIF(TRIM(Payment_Plan_Colour),'')                            AS Colour,
            NULLIF(TRIM(Payment_Plan_Site_Id),'')                           AS Site_ID,
            CAST(Dentist_Recall_Interval AS INT)                            AS Dentist_Recall_Interval_Months,
            CAST(Hygienist_Recall_Interval AS INT)                          AS Hygienist_Recall_Interval_Months,
            CAST(Emergency_Duration AS INT)                                 AS Emergency_Duration_Mins,
            CAST(Exam_Duration AS INT)                                      AS Exam_Duration_Mins,
            CAST(Exam_Scale_And_Polish_Duration AS INT)                     AS Exam_Scale_Polish_Duration_Mins,
            CAST(Scale_And_Polish_Duration AS INT)                          AS Scale_Polish_Duration_Mins,
            TRY_CAST(Payment_Plan_Created_At AS datetime2(3))               AS Created_Date
        INTO #src
        FROM Silver.Payment_Plans
        WHERE Payment_Plan_Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Payment_Plans tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Payment_Plan_ID = tgt.Payment_Plan_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Payment_Plan_Name               = src.Payment_Plan_Name,
            Patient_Friendly_Name           = src.Patient_Friendly_Name,
            Active                          = src.Active,
            Colour                          = src.Colour,
            Site_ID                         = src.Site_ID,
            Dentist_Recall_Interval_Months  = src.Dentist_Recall_Interval_Months,
            Hygienist_Recall_Interval_Months= src.Hygienist_Recall_Interval_Months,
            Emergency_Duration_Mins         = src.Emergency_Duration_Mins,
            Exam_Duration_Mins              = src.Exam_Duration_Mins,
            Exam_Scale_Polish_Duration_Mins = src.Exam_Scale_Polish_Duration_Mins,
            Scale_Polish_Duration_Mins      = src.Scale_Polish_Duration_Mins,
            DW_Updated_At                   = SYSUTCDATETIME()
        FROM Gold.Dim_Payment_Plans tgt
        INNER JOIN #src src ON tgt.Payment_Plan_ID = src.Payment_Plan_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Payment_Plan_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Friendly_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Emergency_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Exam_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Exam_Scale_Polish_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Scale_Polish_Duration_Mins] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Payment_Plan_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Friendly_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Recall_Interval_Months] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Emergency_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Exam_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Exam_Scale_Polish_Duration_Mins] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Scale_Polish_Duration_Mins] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Dim_Payment_Plans (
            Payment_Plan_ID, Payment_Plan_Name, Patient_Friendly_Name, Active, Colour, Site_ID,
            Dentist_Recall_Interval_Months, Hygienist_Recall_Interval_Months,
            Emergency_Duration_Mins, Exam_Duration_Mins, Exam_Scale_Polish_Duration_Mins,
            Scale_Polish_Duration_Mins, Created_Date, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Payment_Plan_ID, src.Payment_Plan_Name, src.Patient_Friendly_Name, src.Active, src.Colour, src.Site_ID,
            src.Dentist_Recall_Interval_Months, src.Hygienist_Recall_Interval_Months,
            src.Emergency_Duration_Mins, src.Exam_Duration_Mins, src.Exam_Scale_Polish_Duration_Mins,
            src.Scale_Polish_Duration_Mins, src.Created_Date, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Payment_Plans tgt WHERE tgt.Payment_Plan_ID = src.Payment_Plan_ID);
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
