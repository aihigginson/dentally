--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Create_Dim_Users
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *03     01/05/2026  AIH Add missing Is_Current BIT NOT NULL column to CREATE TABLE
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Create_Dim_Users @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Create_Dim_Users]
GO
CREATE PROCEDURE [Gold].[usp_Create_Dim_Users]
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

    DROP TABLE IF EXISTS Gold.Dim_Users;
    CREATE TABLE Gold.Dim_Users (
        pk_User                BIGINT            NOT NULL,
        Tenant_ID                      INT             NOT NULL,
        bk_User_ID             INT               NOT NULL,           -- Natural key from Bronze
        Title                  VARCHAR(50)      NULL,
        First_Name             VARCHAR(100)     NULL,
        Middle_Name            VARCHAR(100)     NULL,
        Last_Name              VARCHAR(100)     NULL,
        Full_Name              VARCHAR(255)     NULL,
        Email                  VARCHAR(255)     NULL,
        Mobile_Phone           VARCHAR(50)      NULL,
        Role                   VARCHAR(100)     NULL,
        Permission_Level       INT               NULL,
        Practice_ID            VARCHAR(255)     NULL,
        Site_ID                VARCHAR(255)     NULL,
        Image_URL              VARCHAR(255)     NULL,
        Last_Login_Date        DATE              NULL,
        Created_Date           datetime2(3) NULL,
        Updated_Date           datetime2(3) NULL,
        DW_Created_At          datetime2(6)      NOT NULL,
        DW_Updated_At          datetime2(6)      NOT NULL,
        Is_Current             BIT               NOT NULL
    );

        -- Insert -1 unknown/shared seed row
        INSERT INTO Gold.Dim_Users (pk_User, Tenant_ID, bk_User_ID, DW_Created_At, DW_Updated_At, Is_Current)
        VALUES (-1, -1, -1, SYSUTCDATETIME(), SYSUTCDATETIME(), 0);

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
