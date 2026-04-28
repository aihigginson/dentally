/****** Object:  StoredProcedure [Gold].[usp_Create_Dim_Practice_Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Dim_Practice_Sites
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Practice_Sites]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Practice_Sites]
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

    DROP TABLE IF EXISTS Gold.Dim_Practice_Sites;

    CREATE TABLE Gold.Dim_Practice_Sites (
        pk_Practice_Site              INT             NOT NULL IDENTITY,
        Site_ID                       VARCHAR(50)    NOT NULL,
        Site_Name                     VARCHAR(255)   NULL,
        Site_Active                   BIT             NULL,
        Site_Address_Line_1           VARCHAR(255)   NULL,
        Site_Address_Line_2           VARCHAR(255)   NULL,
        Site_Town                     VARCHAR(100)   NULL,
        Site_Postcode                 VARCHAR(20)    NULL,
        Site_Phone                    VARCHAR(50)    NULL,
        Site_Website                  VARCHAR(255)   NULL,
        Site_Logo_URL                 VARCHAR(255)   NULL,
        Site_Default_Payment_Plan_ID  INT             NULL,
        Mon_Open                      TIME(0)            NULL,
        Mon_Close                     TIME(0)            NULL,
        Tue_Open                      TIME(0)            NULL,
        Tue_Close                     TIME(0)            NULL,
        Wed_Open                      TIME(0)            NULL,
        Wed_Close                     TIME(0)            NULL,
        Thu_Open                      TIME(0)            NULL,
        Thu_Close                     TIME(0)            NULL,
        Fri_Open                      TIME(0)            NULL,
        Fri_Close                     TIME(0)            NULL,
        Practice_ID                   VARCHAR(255)   NULL,
        Practice_Name                 VARCHAR(255)   NULL,
        Practice_Address_Line_1       VARCHAR(255)   NULL,
        Practice_Address_Line_2       VARCHAR(255)   NULL,
        Practice_Town                 VARCHAR(100)   NULL,
        Practice_Postcode             VARCHAR(20)    NULL,
        Practice_Phone                VARCHAR(50)    NULL,
        Practice_Email                VARCHAR(255)   NULL,
        Practice_Website              VARCHAR(255)   NULL,
        Practice_NHS                  BIT             NULL,
        Practice_Time_Zone            VARCHAR(100)   NULL,
        DW_Created_At                 datetime2(6)    NOT NULL,
        DW_Updated_At                 datetime2(6)    NOT NULL
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
