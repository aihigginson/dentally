/****** Object:  StoredProcedure [Gold].[usp_Create_Dim_Payment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Dim_Payment_Plans
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Payment_Plans]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Payment_Plans]
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
    -- Local counters
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;    
    SET NOCOUNT ON;    
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************


    DROP TABLE IF EXISTS Gold.Dim_Payment_Plans;

    CREATE TABLE Gold.Dim_Payment_Plans (
        pk_Payment_Plan        INT             NOT NULL IDENTITY,
        Payment_Plan_ID        INT             NOT NULL,
        Payment_Plan_Name      VARCHAR(255)   NULL,
        Patient_Friendly_Name  VARCHAR(255)   NULL,
        Active                 BIT             NULL,
        Colour                 VARCHAR(20)    NULL,
        Site_ID                VARCHAR(50)    NULL,
        Dentist_Recall_Interval_Months   INT   NULL,
        Hygienist_Recall_Interval_Months INT   NULL,
        Emergency_Duration_Mins          INT   NULL,
        Exam_Duration_Mins               INT   NULL,
        Exam_Scale_Polish_Duration_Mins  INT   NULL,
        Scale_Polish_Duration_Mins       INT   NULL,
        Created_Date           datetime2(3) NULL,
        DW_Created_At          datetime2(6)    NOT NULL,
        DW_Updated_At          datetime2(6)    NOT NULL
    );

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************


    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Inserts  

END

GO
