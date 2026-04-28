/****** Object:  StoredProcedure [Gold].[usp_Create_Fact_Contracts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

------------------------------------------------------------
-- Gold.usp_Create_Fact_Contracts
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Fact_Contracts]
GO
CREATE PROCEDURE [Gold].[usp_Create_Fact_Contracts]
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

    DROP TABLE IF EXISTS Gold.Fact_Contracts;

    CREATE TABLE Gold.Fact_Contracts (
        pk_Contract                 INT               NOT NULL IDENTITY,
        bk_Contract_ID              VARCHAR(50)      NOT NULL,   -- Natural key from Silver.Nhs_Claims

        fk_Practice_Site            INT               NULL,
        fk_Date_Start               INT               NULL,
        fk_Date_End                 INT               NULL,

        Contract_Number             INT               NULL,
        NHS_Location_ID             INT               NULL,
        NHS_Site_ID                 INT               NULL,
        Site_ID                     VARCHAR(255)     NULL,
        Active                      BIT               NULL,
        PDS_Plus                    BIT               NULL,
        Start_Date                  DATE              NULL,
        End_Date                    DATE              NULL,

        UDA_Target                  DECIMAL(18,4)     NULL,
        UDA_Value                   DECIMAL(18,4)     NULL,
        UOA_Target                  DECIMAL(18,4)     NULL,
        UOA_Value                   DECIMAL(18,4)     NULL,

        DW_Created_At               datetime2(6)      NOT NULL,
        DW_Updated_At               datetime2(6)      NOT NULL
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
