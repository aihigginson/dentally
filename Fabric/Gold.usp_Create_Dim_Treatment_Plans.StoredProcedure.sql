/****** Object:  StoredProcedure [Gold].[usp_Create_Dim_Treatment_Plans]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Dim_Treatment_Plans
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Treatment_Plans]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Treatment_Plans]
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

    DROP TABLE IF EXISTS Gold.Dim_Treatment_Plans;

    CREATE TABLE Gold.Dim_Treatment_Plans (
        pk_Treatment_Plan          INT               NOT NULL IDENTITY,
        Treatment_Plan_ID          INT               NOT NULL,
        Nickname                   VARCHAR(255)     NULL,
        Patient_ID                 INT               NULL,
        Practitioner_ID            INT               NULL,
        Completed                  BIT               NULL,
        Start_Date                 DATE              NULL,
        End_Date                   DATE              NULL,
        Completed_Date             datetime2(3) NULL,
        Last_Completed_Date        DATE              NULL,
        NHS_UDA_Value              DECIMAL(18,4)     NULL,
        NHS_Completed_UDA_Value    DECIMAL(18,4)     NULL,
        Private_Treatment_Value    DECIMAL(18,4)     NULL,
        Created_Date               datetime2(3) NULL,
        Updated_Date               datetime2(3) NULL,
        DW_Created_At              datetime2(6)      NOT NULL,
        DW_Updated_At              datetime2(6)      NOT NULL
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
