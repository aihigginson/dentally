/****** Object:  StoredProcedure [Gold].[usp_Create_Dim_Practitioners]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Dim_Practitioners
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Practitioners]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Practitioners]
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
    DROP TABLE IF EXISTS Gold.Dim_Practitioners;

    CREATE TABLE Gold.Dim_Practitioners (
        pk_Practitioner              INT               NOT NULL IDENTITY,
        Practitioner_ID              INT               NOT NULL,
        User_ID                      INT               NULL,
        Title                        VARCHAR(50)      NULL,
        First_Name                   VARCHAR(100)     NULL,
        Middle_Name                  VARCHAR(100)     NULL,
        Last_Name                    VARCHAR(100)     NULL,
        Full_Name                    VARCHAR(255)     NULL,
        Email                        VARCHAR(255)     NULL,
        Mobile_Phone                 VARCHAR(50)      NULL,
        Role                         VARCHAR(100)     NULL,
        Permission_Level             INT               NULL,
        Active                       BIT               NULL,
        Colour                       VARCHAR(50)      NULL,
        GDC_Number                   VARCHAR(50)      NULL,
        NHS_Number                   VARCHAR(50)      NULL,
        Site_ID                      VARCHAR(50)      NULL,
        Default_Contract_ID          VARCHAR(255)     NULL,
        Contract_Targets_String      VARCHAR(255)     NULL,
        Image_URL                    VARCHAR(255)     NULL,
        Last_Login_Date              DATE              NULL,
        Created_Date                 datetime2(3) NULL,
        Updated_Date                 datetime2(3) NULL,
        DW_Created_At                datetime2(6)      NOT NULL,
        DW_Updated_At                datetime2(6)      NOT NULL
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
