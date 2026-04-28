/****** Object:  StoredProcedure [Gold].[usp_Create_Dim_Accounts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Dim_Accounts
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Accounts]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Accounts]
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

    DROP TABLE IF EXISTS Gold.Dim_Accounts;

    CREATE TABLE Gold.Dim_Accounts (
        pk_Account                         INT             NOT NULL IDENTITY,
        Account_ID                         INT             NOT NULL,
        Patient_ID                         INT             NULL,
        Patient_Name                       VARCHAR(255)   NULL,
        Current_Balance                    DECIMAL(18,4)   NULL,
        Opening_Balance                    DECIMAL(18,4)   NULL,
        Planned_NHS_Treatment_Value        DECIMAL(18,4)   NULL,
        Planned_Private_Treatment_Value    DECIMAL(18,4)   NULL,
        DW_Created_At                      datetime2(6)    NOT NULL,
        DW_Updated_At                      datetime2(6)    NOT NULL
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
